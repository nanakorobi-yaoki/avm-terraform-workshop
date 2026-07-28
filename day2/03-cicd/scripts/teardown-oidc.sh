#!/usr/bin/env bash
# =============================================================================
# OIDC セットアップの後片付け
# =============================================================================
# アプリ登録（＋サービスプリンシパル、Federated Credential）と
# デモ用リソースグループを削除します。
#
# 使い方:
#   ./teardown-oidc.sh --app-name gh-oidc-contoso-org-avm-workshop \
#                      --resource-group rg-avm-cicd-demo
# =============================================================================

set -euo pipefail

APP_NAME=""
RESOURCE_GROUP=""
YES=false

usage() {
  echo "使い方: $0 --app-name <アプリ名> [--resource-group <RG名>] [--yes]"
  exit 1
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app-name)       APP_NAME="$2"; shift 2 ;;
    --resource-group) RESOURCE_GROUP="$2"; shift 2 ;;
    --yes)            YES=true; shift ;;
    -h|--help)        usage ;;
    *) echo "不明な引数: $1" >&2; usage ;;
  esac
done

[[ -z "$APP_NAME" ]] && usage

echo "以下を削除します:"
echo "  - Entra ID アプリ登録: ${APP_NAME}"
[[ -n "$RESOURCE_GROUP" ]] && echo "  - リソースグループ    : ${RESOURCE_GROUP} (中のリソースも全て削除されます)"
echo

if [[ "$YES" != true ]]; then
  read -r -p "続行しますか? [y/N] " answer
  [[ "$answer" =~ ^[Yy]$ ]] || { echo "中止しました"; exit 0; }
fi

APP_ID=$(az ad app list --display-name "$APP_NAME" --query "[0].appId" -o tsv 2>/dev/null || true)

if [[ -n "$APP_ID" && "$APP_ID" != "null" ]]; then
  az ad app delete --id "$APP_ID"
  echo "✔ アプリ登録を削除しました: ${APP_ID}"
else
  echo "- アプリ登録が見つかりません: ${APP_NAME}"
fi

if [[ -n "$RESOURCE_GROUP" ]]; then
  if az group exists --name "$RESOURCE_GROUP" | grep -q true; then
    az group delete --name "$RESOURCE_GROUP" --yes --no-wait
    echo "✔ リソースグループの削除を開始しました（非同期）: ${RESOURCE_GROUP}"
  else
    echo "- リソースグループが見つかりません: ${RESOURCE_GROUP}"
  fi
fi

echo "完了"
