#!/usr/bin/env bash
# =============================================================================
# GitHub Actions ⇄ Azure  OIDC (Workload Identity Federation) 一括セットアップ
# =============================================================================
# 実行内容:
#   1. Entra ID アプリ登録 + サービスプリンシパル作成
#   2. リソースグループ作成（最小権限スコープ用）
#   3. RBAC 割り当て（RG スコープ / サブスクリプション全体ではない）
#   4. Federated Credential を 4 種類登録
#        - main ブランチ push 用
#        - pull_request 用
#        - environment:production 用   ← 承認ゲート付きジョブに必須
#        - environment:plan 用
#   5. gh CLI があれば GitHub Secrets を自動登録
#
# 前提: az CLI ログイン済み (`az login`)、アプリ登録権限があること
# 使い方:
#   ./setup-oidc.sh --org contoso-org --repo avm-workshop \
#                   --subscription <SUB_ID> --resource-group rg-avm-cicd-demo
# =============================================================================

set -euo pipefail

APP_NAME=""
GITHUB_ORG=""
GITHUB_REPO=""
SUBSCRIPTION_ID=""
RESOURCE_GROUP=""
LOCATION="japaneast"
ROLE="Contributor"

usage() {
  cat <<EOF
使い方: $0 --org <GitHub Org> --repo <Repo名> --subscription <Sub ID> --resource-group <RG名> [オプション]

必須:
  --org               GitHub の Organization または ユーザー名
  --repo              リポジトリ名
  --subscription      Azure サブスクリプション ID
  --resource-group    RBAC を割り当てるリソースグループ名

オプション:
  --app-name          Entra ID アプリ名 (既定: gh-oidc-<org>-<repo>)
  --location          リージョン (既定: japaneast)
  --role              割り当てるロール (既定: Contributor)
  -h, --help          このヘルプ
EOF
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --org)            GITHUB_ORG="$2"; shift 2 ;;
    --repo)           GITHUB_REPO="$2"; shift 2 ;;
    --subscription)   SUBSCRIPTION_ID="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --app-name)       APP_NAME="$2"; shift 2 ;;
    --location)       LOCATION="$2"; shift 2 ;;
    --role)           ROLE="$2"; shift 2 ;;
    -h|--help)        usage ;;
    *) echo "不明な引数: $1" >&2; usage ;;
  esac
done

[[ -z "$GITHUB_ORG" || -z "$GITHUB_REPO" || -z "$SUBSCRIPTION_ID" || -z "$RESOURCE_GROUP" ]] && usage

APP_NAME="${APP_NAME:-gh-oidc-${GITHUB_ORG}-${GITHUB_REPO}}"
REPO_FULL="${GITHUB_ORG}/${GITHUB_REPO}"

echo "=============================================="
echo " OIDC セットアップ"
echo "=============================================="
echo " アプリ名        : ${APP_NAME}"
echo " リポジトリ      : ${REPO_FULL}"
echo " サブスクリプション: ${SUBSCRIPTION_ID}"
echo " リソースグループ : ${RESOURCE_GROUP} (${LOCATION})"
echo " ロール          : ${ROLE}"
echo "=============================================="
echo

az account set --subscription "$SUBSCRIPTION_ID"

# -----------------------------------------------------------------------------
# 1. アプリ登録（冪等: 既存があれば再利用）
# -----------------------------------------------------------------------------
echo "▶ [1/5] Entra ID アプリ登録..."
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  echo "   作成しました: ${APP_ID}"
else
  echo "   既存を再利用: ${APP_ID}"
fi

# -----------------------------------------------------------------------------
# 2. サービスプリンシパル
# -----------------------------------------------------------------------------
echo "▶ [2/5] サービスプリンシパル..."
SP_ID=$(az ad sp list --filter "appId eq '${APP_ID}'" --query "[0].id" -o tsv 2>/dev/null || true)

if [[ -z "$SP_ID" || "$SP_ID" == "null" ]]; then
  SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)
  echo "   作成しました: ${SP_ID}"
  echo "   (レプリケーション待機 15 秒)"
  sleep 15
else
  echo "   既存を再利用: ${SP_ID}"
fi

# -----------------------------------------------------------------------------
# 3. リソースグループ + RBAC（最小権限: RG スコープ）
# -----------------------------------------------------------------------------
echo "▶ [3/5] リソースグループと RBAC..."
az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output none
SCOPE="/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}"

if az role assignment list --assignee "$SP_ID" --scope "$SCOPE" --query "[?roleDefinitionName=='${ROLE}']" -o tsv | grep -q .; then
  echo "   RBAC は割り当て済み"
else
  az role assignment create \
    --assignee-object-id "$SP_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "$ROLE" \
    --scope "$SCOPE" \
    --output none
  echo "   ${ROLE} を ${RESOURCE_GROUP} に割り当てました"
fi

# -----------------------------------------------------------------------------
# 4. Federated Credentials
#    ★ subject が JWT の sub クレームと完全一致する必要がある
# -----------------------------------------------------------------------------
echo "▶ [4/5] Federated Credential..."

add_federated_credential() {
  local name="$1" subject="$2" desc="$3"

  if az ad app federated-credential list --id "$APP_ID" --query "[?name=='${name}']" -o tsv 2>/dev/null | grep -q .; then
    echo "   スキップ (既存): ${name}"
    return
  fi

  az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"${name}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${subject}\",
    \"description\": \"${desc}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none

  echo "   登録: ${name}"
  echo "         subject = ${subject}"
}

add_federated_credential "github-main"        "repo:${REPO_FULL}:ref:refs/heads/main"    "main ブランチへの push"
add_federated_credential "github-pr"          "repo:${REPO_FULL}:pull_request"           "Pull Request"
add_federated_credential "github-env-prod"    "repo:${REPO_FULL}:environment:production" "environment: production (承認ゲート)"
add_federated_credential "github-env-plan"    "repo:${REPO_FULL}:environment:plan"       "environment: plan"

# -----------------------------------------------------------------------------
# 5. GitHub Secrets 登録（gh CLI があれば自動）
# -----------------------------------------------------------------------------
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "▶ [5/5] GitHub Secrets..."
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh secret set AZURE_CLIENT_ID       --repo "$REPO_FULL" --body "$APP_ID"
  gh secret set AZURE_TENANT_ID       --repo "$REPO_FULL" --body "$TENANT_ID"
  gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO_FULL" --body "$SUBSCRIPTION_ID"
  echo "   gh CLI で自動登録しました"
else
  echo "   gh CLI が無い / 未認証のため手動で登録してください"
fi

cat <<EOF

==============================================
 完了
==============================================
GitHub Secrets に以下を設定してください
（いずれも機密情報ではありません。Client Secret は存在しません）

  AZURE_CLIENT_ID       = ${APP_ID}
  AZURE_TENANT_ID       = ${TENANT_ID}
  AZURE_SUBSCRIPTION_ID = ${SUBSCRIPTION_ID}

次の手順:
  1. GitHub リポジトリで Environment "production" と "plan" を作成
     Settings > Environments > New environment
  2. "production" に Required reviewers を設定（承認ゲート）
  3. PR を作成してワークフローの動作を確認

⚠ 注意: ジョブに environment: を指定すると JWT の sub クレームが
        environment:<名前> に変わります。本スクリプトは production と
        plan の 2 つを登録済みです。別名の environment を使う場合は
        追加登録が必要です。

後片付け: ./teardown-oidc.sh --app-name "${APP_NAME}" --resource-group "${RESOURCE_GROUP}"
==============================================
EOF
