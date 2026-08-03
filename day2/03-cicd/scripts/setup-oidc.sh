#!/usr/bin/env bash
# =============================================================================
# GitHub Actions ⇄ Azure  OIDC (Workload Identity Federation) 一括セットアップ
# =============================================================================
# 実行内容:
#   1. Entra ID アプリ登録 + サービスプリンシパル作成
#   2. リソースグループ作成（最小権限スコープ用）
#   3. RBAC 割り当て（RG スコープ / サブスクリプション全体ではない）
#   4. Azure Blob state backend を作成
#   5. Federated Credential を 4 種類登録
#        - main ブランチ push 用
#        - pull_request 用
#        - environment:production 用   ← 承認ゲート付きジョブに必須
#        - environment:plan 用
#      ※ subject の接頭辞は GitHub API から実値を取得し、古典形式と
#        ID 形式の両方を登録します（合計最大 8 件）
#   6. gh CLI があれば GitHub Secrets / Variables を自動登録
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
BACKEND_RESOURCE_GROUP="rg-terraform-state"
BACKEND_STORAGE_ACCOUNT=""
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
  --backend-resource-group State 用リソースグループ名 (既定: rg-terraform-state)
  --backend-storage-account State 用 Storage Account 名 (既定: App ID から生成)
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
    --backend-resource-group) BACKEND_RESOURCE_GROUP="$2"; shift 2 ;;
    --backend-storage-account) BACKEND_STORAGE_ACCOUNT="$2"; shift 2 ;;
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
echo "▶ [1/6] Entra ID アプリ登録..."
APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [[ -z "$APP_ID" || "$APP_ID" == "null" ]]; then
  APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
  echo "   作成しました: ${APP_ID}"
else
  echo "   既存を再利用: ${APP_ID}"
fi

if [[ -z "$BACKEND_STORAGE_ACCOUNT" ]]; then
  BACKEND_STORAGE_ACCOUNT="sttf${APP_ID//-/}"
  BACKEND_STORAGE_ACCOUNT="${BACKEND_STORAGE_ACCOUNT:0:24}"
fi

# -----------------------------------------------------------------------------
# 2. サービスプリンシパル
# -----------------------------------------------------------------------------
echo "▶ [2/6] サービスプリンシパル..."
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
echo "▶ [3/6] リソースグループと RBAC..."
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
# 4. Azure Blob Backend（state はデプロイ先と分離）
# -----------------------------------------------------------------------------
echo "▶ [4/6] Terraform state backend..."
az group create --name "$BACKEND_RESOURCE_GROUP" --location "$LOCATION" --output none
az storage account create \
  --name "$BACKEND_STORAGE_ACCOUNT" \
  --resource-group "$BACKEND_RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2 \
  --output none
az storage container create \
  --name tfstate \
  --account-name "$BACKEND_STORAGE_ACCOUNT" \
  --auth-mode key \
  --output none

STORAGE_ID=$(az storage account show --name "$BACKEND_STORAGE_ACCOUNT" --resource-group "$BACKEND_RESOURCE_GROUP" --query id -o tsv)
if ! az role assignment list --assignee "$SP_ID" --scope "$STORAGE_ID" --query "[?roleDefinitionName=='Storage Blob Data Contributor']" -o tsv | grep -q .; then
  az role assignment create \
    --assignee-object-id "$SP_ID" \
    --assignee-principal-type ServicePrincipal \
    --role "Storage Blob Data Contributor" \
    --scope "$STORAGE_ID" \
    --output none
fi

# -----------------------------------------------------------------------------
# 4. Federated Credentials
#    ★ subject が JWT の sub クレームと完全一致する必要がある
# -----------------------------------------------------------------------------
echo "▶ [5/6] Federated Credential..."

add_federated_credential() {
  local name="$1" subject="$2" desc="$3"

  # ★ 重複判定は「名前」ではなく「subject」で行う
  #   Entra ID は issuer + subject の組み合わせに一意性制約を課すため、
  #   名前で判定すると "must be unique for the application" エラーになります。
  local existing
  existing=$(az ad app federated-credential list --id "$APP_ID" --query "[?subject=='${subject}'].name" -o tsv 2>/dev/null || true)
  if [[ -n "$existing" ]]; then
    echo "   スキップ (subject 登録済み: ${existing})"
    return
  fi

  if az ad app federated-credential create --id "$APP_ID" --parameters "{
    \"name\": \"${name}\",
    \"issuer\": \"https://token.actions.githubusercontent.com\",
    \"subject\": \"${subject}\",
    \"description\": \"${desc}\",
    \"audiences\": [\"api://AzureADTokenExchange\"]
  }" --output none; then
    echo "   登録: ${name}"
    echo "         subject = ${subject}"
  else
    echo "   ✗ 登録失敗: ${name} (subject = ${subject})" >&2
    return 1
  fi
}

# -----------------------------------------------------------------------------
# ★★★ 最重要 ★★★  subject の接頭辞は「推測しない」
#
# GitHub は sub クレームの接頭辞を、古典的な
#     repo:<org>/<repo>
# ではなく、数値 ID を含む不変 (immutable) 形式
#     repo:<org>@<orgId>/<repo>@<repoId>
# で発行することがあります。
# しかも customization/sub の use_immutable_subject が false でも
# ID 形式になるケースが実際に確認されています。
#
# subject が 1 文字でも違うと実行時にこうなります:
#     AADSTS700213: No matching federated identity record found
#
# → GitHub API から sub_claim_prefix を取得し、両形式を登録します。
# -----------------------------------------------------------------------------
PREFIXES=("repo:${REPO_FULL}")

if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  ACTUAL_PREFIX=$(gh api "repos/${REPO_FULL}/actions/oidc/customization/sub" --jq '.sub_claim_prefix' 2>/dev/null || true)
  if [[ -n "$ACTUAL_PREFIX" && "$ACTUAL_PREFIX" != "null" && "$ACTUAL_PREFIX" != "repo:${REPO_FULL}" ]]; then
    echo "   ⚠ GitHub は ID 形式の sub を発行します"
    echo "     検出した接頭辞: ${ACTUAL_PREFIX}"
    PREFIXES+=("$ACTUAL_PREFIX")
  fi
else
  echo "   ⚠ gh CLI が無い / 未認証のため接頭辞を検出できません。古典形式のみ登録します"
fi

IDX=0
for PREFIX in "${PREFIXES[@]}"; do
  # 2 つ目以降（ID 形式）は名前が衝突しないよう接尾辞を付ける
  if [[ $IDX -eq 0 ]]; then SFX=""; else SFX="-id"; fi

  add_federated_credential "github-main${SFX}"     "${PREFIX}:ref:refs/heads/main"    "main ブランチへの push"
  add_federated_credential "github-pr${SFX}"       "${PREFIX}:pull_request"           "Pull Request"
  add_federated_credential "github-env-prod${SFX}" "${PREFIX}:environment:production" "environment: production (承認ゲート)"
  add_federated_credential "github-env-plan${SFX}" "${PREFIX}:environment:plan"       "environment: plan"

  IDX=$((IDX + 1))
done

# -----------------------------------------------------------------------------
# 5. GitHub Secrets 登録（gh CLI があれば自動）
# -----------------------------------------------------------------------------
TENANT_ID=$(az account show --query tenantId -o tsv)

echo "▶ [6/6] GitHub Secrets / Variables..."
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh secret set AZURE_CLIENT_ID       --repo "$REPO_FULL" --body "$APP_ID"
  gh secret set AZURE_TENANT_ID       --repo "$REPO_FULL" --body "$TENANT_ID"
  gh secret set AZURE_SUBSCRIPTION_ID --repo "$REPO_FULL" --body "$SUBSCRIPTION_ID"
  gh variable set DEPLOYMENT_RESOURCE_GROUP --repo "$REPO_FULL" --body "$RESOURCE_GROUP"
  gh variable set TFSTATE_RESOURCE_GROUP     --repo "$REPO_FULL" --body "$BACKEND_RESOURCE_GROUP"
  gh variable set TFSTATE_STORAGE_ACCOUNT    --repo "$REPO_FULL" --body "$BACKEND_STORAGE_ACCOUNT"
  gh variable set TFSTATE_CONTAINER          --repo "$REPO_FULL" --body "tfstate"
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

GitHub Variables:
  DEPLOYMENT_RESOURCE_GROUP = ${RESOURCE_GROUP}
  TFSTATE_RESOURCE_GROUP     = ${BACKEND_RESOURCE_GROUP}
  TFSTATE_STORAGE_ACCOUNT    = ${BACKEND_STORAGE_ACCOUNT}
  TFSTATE_CONTAINER          = tfstate

次の手順:
  1. GitHub リポジトリで Environment "production" と "plan" を作成
     Settings > Environments > New environment
  2. "production" に Required reviewers を設定（承認ゲート）
  3. PR を作成してワークフローの動作を確認

⚠ 注意 1: ジョブに environment: を指定すると JWT の sub クレームが
           environment:<名前> に変わります。本スクリプトは production と
           plan の 2 つを登録済みです。別名の environment を使う場合は
           追加登録が必要です。

⚠ 注意 2: GitHub は sub の接頭辞を ID 形式
           (repo:<org>@<orgId>/<repo>@<repoId>) で発行することがあります。
           本スクリプトは両形式を登録します。認証に失敗したら、
           実際の sub を Actions のログ（Azure Login ステップ）で確認し、
           下記で接頭辞を照合してください:
             gh api repos/${REPO_FULL}/actions/oidc/customization/sub --jq .sub_claim_prefix

後片付け: ./teardown-oidc.sh --app-name "${APP_NAME}" --resource-group "${RESOURCE_GROUP}"
==============================================
EOF
