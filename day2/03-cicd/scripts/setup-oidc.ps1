<#
.SYNOPSIS
    GitHub Actions ⇄ Azure の OIDC (Workload Identity Federation) を一括セットアップします。

.DESCRIPTION
    以下を冪等に実行します。
      1. Entra ID アプリ登録 + サービスプリンシパル作成
      2. リソースグループ作成（最小権限スコープ用）
      3. RBAC 割り当て（RG スコープ / サブスクリプション全体ではない）
      4. Federated Credential を 4 種類登録
           - main ブランチ push 用
           - pull_request 用
           - environment:production 用   ← 承認ゲート付きジョブに必須
           - environment:plan 用
      5. gh CLI があれば GitHub Secrets を自動登録

    前提: az CLI ログイン済み (az login)、アプリ登録権限があること

.EXAMPLE
    ./setup-oidc.ps1 -GitHubOrg "contoso-org" -GitHubRepo "avm-workshop" `
                     -SubscriptionId "00000000-0000-0000-0000-000000000000" `
                     -ResourceGroupName "rg-avm-cicd-demo"
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string] $GitHubOrg,
    [Parameter(Mandatory)][string] $GitHubRepo,
    [Parameter(Mandatory)][string] $SubscriptionId,
    [Parameter(Mandatory)][string] $ResourceGroupName,
    [string] $AppName,
    [string] $Location = "japaneast",
    [string] $Role     = "Contributor"
)

$ErrorActionPreference = "Stop"

if (-not $AppName) { $AppName = "gh-oidc-$GitHubOrg-$GitHubRepo" }
$RepoFull = "$GitHubOrg/$GitHubRepo"

Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " OIDC セットアップ" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " アプリ名          : $AppName"
Write-Host " リポジトリ        : $RepoFull"
Write-Host " サブスクリプション : $SubscriptionId"
Write-Host " リソースグループ   : $ResourceGroupName ($Location)"
Write-Host " ロール            : $Role"
Write-Host ""

az account set --subscription $SubscriptionId | Out-Null

# -----------------------------------------------------------------------------
# 1. アプリ登録（冪等）
# -----------------------------------------------------------------------------
Write-Host "▶ [1/5] Entra ID アプリ登録..." -ForegroundColor Yellow
$appId = az ad app list --display-name $AppName --query "[0].appId" -o tsv

if ([string]::IsNullOrWhiteSpace($appId)) {
    $appId = az ad app create --display-name $AppName --query appId -o tsv
    Write-Host "   作成しました: $appId"
} else {
    Write-Host "   既存を再利用: $appId"
}

# -----------------------------------------------------------------------------
# 2. サービスプリンシパル
# -----------------------------------------------------------------------------
Write-Host "▶ [2/5] サービスプリンシパル..." -ForegroundColor Yellow
$spId = az ad sp list --filter "appId eq '$appId'" --query "[0].id" -o tsv

if ([string]::IsNullOrWhiteSpace($spId)) {
    $spId = az ad sp create --id $appId --query id -o tsv
    Write-Host "   作成しました: $spId"
    Write-Host "   (レプリケーション待機 15 秒)"
    Start-Sleep -Seconds 15
} else {
    Write-Host "   既存を再利用: $spId"
}

# -----------------------------------------------------------------------------
# 3. リソースグループ + RBAC（最小権限: RG スコープ）
# -----------------------------------------------------------------------------
Write-Host "▶ [3/5] リソースグループと RBAC..." -ForegroundColor Yellow
az group create --name $ResourceGroupName --location $Location --output none
$scope = "/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName"

$existing = az role assignment list --assignee $spId --scope $scope `
                --query "[?roleDefinitionName=='$Role']" -o tsv

if ([string]::IsNullOrWhiteSpace($existing)) {
    az role assignment create `
        --assignee-object-id $spId `
        --assignee-principal-type ServicePrincipal `
        --role $Role `
        --scope $scope `
        --output none
    Write-Host "   $Role を $ResourceGroupName に割り当てました"
} else {
    Write-Host "   RBAC は割り当て済み"
}

# -----------------------------------------------------------------------------
# 4. Federated Credentials
#    ★ subject が JWT の sub クレームと完全一致する必要がある
# -----------------------------------------------------------------------------
Write-Host "▶ [4/5] Federated Credential..." -ForegroundColor Yellow

function Add-FederatedCredential {
    param([string]$Name, [string]$Subject, [string]$Description)

    $found = az ad app federated-credential list --id $appId --query "[?name=='$Name']" -o tsv
    if (-not [string]::IsNullOrWhiteSpace($found)) {
        Write-Host "   スキップ (既存): $Name"
        return
    }

    $params = @{
        name        = $Name
        issuer      = "https://token.actions.githubusercontent.com"
        subject     = $Subject
        description = $Description
        audiences   = @("api://AzureADTokenExchange")
    } | ConvertTo-Json -Compress

    # az CLI に JSON を渡すため一時ファイル経由（Windows のクォート問題を回避）
    $tmp = New-TemporaryFile
    Set-Content -Path $tmp -Value $params -Encoding utf8
    az ad app federated-credential create --id $appId --parameters "@$tmp" --output none
    Remove-Item $tmp -Force

    Write-Host "   登録: $Name"
    Write-Host "         subject = $Subject"
}

Add-FederatedCredential -Name "github-main"     -Subject "repo:${RepoFull}:ref:refs/heads/main"    -Description "main ブランチへの push"
Add-FederatedCredential -Name "github-pr"       -Subject "repo:${RepoFull}:pull_request"           -Description "Pull Request"
Add-FederatedCredential -Name "github-env-prod" -Subject "repo:${RepoFull}:environment:production" -Description "environment: production (承認ゲート)"
Add-FederatedCredential -Name "github-env-plan" -Subject "repo:${RepoFull}:environment:plan"       -Description "environment: plan"

# -----------------------------------------------------------------------------
# 5. GitHub Secrets 登録
# -----------------------------------------------------------------------------
$tenantId = az account show --query tenantId -o tsv

Write-Host "▶ [5/5] GitHub Secrets..." -ForegroundColor Yellow
$ghAvailable = $null -ne (Get-Command gh -ErrorAction SilentlyContinue)

if ($ghAvailable) {
    gh secret set AZURE_CLIENT_ID       --repo $RepoFull --body $appId
    gh secret set AZURE_TENANT_ID       --repo $RepoFull --body $tenantId
    gh secret set AZURE_SUBSCRIPTION_ID --repo $RepoFull --body $SubscriptionId
    Write-Host "   gh CLI で自動登録しました"
} else {
    Write-Host "   gh CLI が無いため手動で登録してください"
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Green
Write-Host " 完了" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Green
Write-Host @"
GitHub Secrets に以下を設定してください
（いずれも機密情報ではありません。Client Secret は存在しません）

  AZURE_CLIENT_ID       = $appId
  AZURE_TENANT_ID       = $tenantId
  AZURE_SUBSCRIPTION_ID = $SubscriptionId

次の手順:
  1. GitHub リポジトリで Environment "production" と "plan" を作成
     Settings > Environments > New environment
  2. "production" に Required reviewers を設定（承認ゲート）
  3. PR を作成してワークフローの動作を確認

⚠ 注意: ジョブに environment: を指定すると JWT の sub クレームが
        environment:<名前> に変わります。本スクリプトは production と
        plan の 2 つを登録済みです。別名の environment を使う場合は
        追加登録が必要です。
"@
