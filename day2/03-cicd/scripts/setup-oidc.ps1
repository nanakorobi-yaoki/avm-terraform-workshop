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
         ※ subject の接頭辞は GitHub API から実値を取得し、古典形式と
           ID 形式の両方を登録します（合計最大 8 件）
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

    # ★ 重複判定は「名前」ではなく「subject」で行う
    #   Entra ID は issuer + subject の組み合わせに一意性制約を課します。
    #   名前で判定すると、別名で同じ subject を登録しようとして
    #   "must be unique for the application" エラーになります。
    $existing = az ad app federated-credential list --id $appId --query "[?subject=='$Subject'].name" -o tsv
    if (-not [string]::IsNullOrWhiteSpace($existing)) {
        Write-Host "   スキップ (subject 登録済み: $($existing.Trim()))"
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
    $ok = ($LASTEXITCODE -eq 0)
    Remove-Item $tmp -Force

    if ($ok) {
        Write-Host "   登録: $Name"
        Write-Host "         subject = $Subject"
    } else {
        Write-Host "   ✗ 登録失敗: $Name (subject = $Subject)" -ForegroundColor Red
    }
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
# subject は 1 文字でも違うと実行時にこうなります:
#     AADSTS700213: No matching federated identity record found
#
# → GitHub API から sub_claim_prefix を取得し、実際の形式を使います。
#   両形式を登録しておけば、GitHub 側の仕様変更にも耐えられます。
# -----------------------------------------------------------------------------
$ghAvailable = $null -ne (Get-Command gh -ErrorAction SilentlyContinue)

$prefixes = [System.Collections.Generic.List[string]]::new()
$prefixes.Add("repo:$RepoFull")

if ($ghAvailable) {
    $actualPrefix = (gh api "repos/$RepoFull/actions/oidc/customization/sub" --jq ".sub_claim_prefix" 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($actualPrefix)) {
        $actualPrefix = $actualPrefix.Trim()
        if (-not $prefixes.Contains($actualPrefix)) {
            Write-Host "   ⚠ GitHub は ID 形式の sub を発行します" -ForegroundColor Magenta
            Write-Host "     検出した接頭辞: $actualPrefix" -ForegroundColor Magenta
            $prefixes.Add($actualPrefix)
        }
    }
} else {
    Write-Host "   ⚠ gh CLI が無いため接頭辞を検出できません。古典形式のみ登録します" -ForegroundColor Yellow
}

$idx = 0
foreach ($prefix in $prefixes) {
    # 2 つ目以降（ID 形式）は名前が衝突しないよう接尾辞を付ける
    $sfx = if ($idx -eq 0) { "" } else { "-id" }

    Add-FederatedCredential -Name "github-main$sfx"     -Subject "${prefix}:ref:refs/heads/main"    -Description "main ブランチへの push"
    Add-FederatedCredential -Name "github-pr$sfx"       -Subject "${prefix}:pull_request"           -Description "Pull Request"
    Add-FederatedCredential -Name "github-env-prod$sfx" -Subject "${prefix}:environment:production" -Description "environment: production (承認ゲート)"
    Add-FederatedCredential -Name "github-env-plan$sfx" -Subject "${prefix}:environment:plan"       -Description "environment: plan"

    $idx++
}

# -----------------------------------------------------------------------------
# 5. GitHub Secrets 登録
# -----------------------------------------------------------------------------
$tenantId = az account show --query tenantId -o tsv

Write-Host "▶ [5/5] GitHub Secrets..." -ForegroundColor Yellow

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

⚠ 注意 1: ジョブに environment: を指定すると JWT の sub クレームが
           environment:<名前> に変わります。本スクリプトは production と
           plan の 2 つを登録済みです。別名の environment を使う場合は
           追加登録が必要です。

⚠ 注意 2: GitHub は sub の接頭辞を ID 形式
           (repo:<org>@<orgId>/<repo>@<repoId>) で発行することがあります。
           本スクリプトは両形式を登録します。認証に失敗したら、
           実際の sub を Actions のログ（Azure Login ステップ）で確認し、
           下記で接頭辞を照合してください:
             gh api repos/$RepoFull/actions/oidc/customization/sub --jq .sub_claim_prefix
"@
