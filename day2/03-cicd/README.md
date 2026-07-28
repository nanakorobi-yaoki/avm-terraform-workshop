# Day 2 — Demo 03: GitHub Actions × Terraform Deep Dive

> 本日の主題です。座学 33 分 + 実演 25 分 = 合計 58 分を配分しています。

## 構成ファイル

| ファイル | 説明 |
|---------|------|
| `.github/workflows/terraform.yml` | 基本形 — Plan on PR / Apply on merge |
| `.github/workflows/reusable-terraform.yml` | ★ **再利用可能ワークフロー**（中央リポジトリに置く本命） |
| `.github/workflows/caller-example.yml` | ★ 各案件リポジトリからの呼び出し例（matrix 展開含む） |
| `.github/workflows/drift-detection.yml` | 定期ドリフト検知（毎日 JST 06:00） |
| `scripts/setup-oidc.sh` | ★ OIDC 一括セットアップ（Bash） |
| `scripts/setup-oidc.ps1` | ★ OIDC 一括セットアップ（PowerShell） |
| `scripts/teardown-oidc.sh` | ★ デモ後のクリーンアップ |
| `policy/tags.rego` | ★ 必須タグの強制（conftest） |
| `policy/security.rego` | ★ セキュリティベースライン（conftest） |
| `.tflint.hcl` | ★ TFLint 設定（azurerm ルールセット） |
| `azure-pipelines.yml` | Azure DevOps 版（比較用） |

---

## 事前準備（デモ開始前に実施済みにしておく）

```powershell
# Windows
.\scripts\setup-oidc.ps1 `
  -GitHubOrg  "your-org" `
  -GitHubRepo "avm-terraform-demo" `
  -SubscriptionId "<SUB_ID>" `
  -ResourceGroupName "rg-avm-demo"
```

```bash
# macOS / Linux
./scripts/setup-oidc.sh \
  --org your-org \
  --repo avm-terraform-demo \
  --subscription <SUB_ID> \
  --resource-group rg-avm-demo
```

このスクリプトは以下を**冪等に**実行します。

1. Entra ID アプリ登録 + Service Principal 作成
2. リソースグループ作成 + **RG スコープ**の RBAC 割り当て（サブスクリプション全体の Contributor は付与しません）
3. **Federated Credential を 4 つ**登録
4. `gh` CLI があれば GitHub Secrets を自動設定

### ⚠️ 最頻出の落とし穴

ジョブに `environment:` を指定すると、GitHub が発行する JWT の `sub` クレームが変わります。

| ジョブの条件 | `sub` の値 |
|---|---|
| main ブランチの push | `repo:ORG/REPO:ref:refs/heads/main` |
| Pull Request | `repo:ORG/REPO:pull_request` |
| `environment: production` 指定時 | `repo:ORG/REPO:environment:production` |

対応する Federated Credential が無いと `AADSTS70021: No matching federated identity record found` で失敗します。上記スクリプトは 4 つすべてを先に登録しています（1 アプリあたり上限 20 件）。

---

## デモの流れ（25 分）

| # | 操作 | 見せどころ | 分 |
|---|------|-----------|---|
| ① | フィーチャーブランチで `main.tf` を編集し PR を作成 | 変更申請書ではなく **PR が申請書になる** | 3 |
| ② | Actions が自動起動 → fmt / validate / tflint / checkov | Azure に繋がず**最速で落とす**設計 | 3 |
| ③ | `plan` 結果が PR に**スティッキーコメント**で投稿される | push するたびにコメントが増えず、常に最新に更新される | 3 |
| ④ ★ | わざとタグを 1 つ消して push | **conftest が PR をブロック。最大の見せ場** | 4 |
| ⑤ | タグを戻して再 push | コメントが更新され、チェックが緑に | 2 |
| ⑥ | PR をマージ | Apply ジョブが起動 → **待機状態**になる | 2 |
| ⑦ ★ | Environment の承認ボタンを押す | **メール承認が GitHub 上の証跡になる。ISMS 対応の核心** | 4 |
| ⑧ | Apply 完了 → Azure Portal で確認 | 承認された plan が**再 plan なしで**適用される | 2 |
| ⑨ | ドリフト検知を手動実行 | Portal での手動変更が Issue として自動起票される | 2 |

> **時間が押した場合**: ④ と ⑦ の 2 つだけは必ず見せてください。この 2 つが「ガードレール」と「証跡」という価値の本質です。

---

## 重要ポイント

### 1. OIDC 認証（Workload Identity Federation）
- Client Secret を**保存しない・失効しない・漏洩しない**
- GitHub が発行する短命 JWT を Entra ID が検証してアクセストークンを発行
- `permissions: id-token: write` + `ARM_USE_OIDC=true` が必須
- GitHub Secrets に入るのは **ID 3 つだけ**（いずれも機密情報ではない）

### 2. Plan → 承認 → Apply
- plan ファイルを**アーティファクトとして渡す**
- apply 時に再 plan しない = **「承認した内容」と「適用した内容」が一致することを保証**
- `-detailed-exitcode` で終了コード判定（`0`=差分なし / `1`=エラー / `2`=差分あり）

### 3. concurrency による直列化

```yaml
concurrency:
  group: terraform-${{ github.ref }}
  cancel-in-progress: false   # ← 必ず false
```

`true` にすると apply 途中でジョブが強制終了され、**Azure 上には作られたが state に無い孤児リソース**が発生します。

### 4. 再利用可能ワークフロー ★ SIer 向けの本命提案

案件リポジトリには `caller-example.yml` の 10 行だけを置き、パイプライン本体は中央で管理します。

- セキュリティスキャンの追加 → **中央 1 回の変更で全案件に反映**
- `@v1.4.0` のタグ固定で、案件ごとに追従タイミングを制御可能
- **考え方は AVM ラッパーモジュールと全く同じ**（中央で標準を持ち、案件は差分だけを持つ）

### 5. Policy as Code

```bash
terraform show -json tfplan > tfplan.json
conftest test tfplan.json --policy policy/
```

| | Azure Policy | conftest |
|---|---|---|
| タイミング | デプロイ時・デプロイ後 | **PR 時（shift-left）** |
| Portal での手動変更 | 検知できる | 検知できない |
| 開発者へのフィードバック | 遅い | 速い |

→ **どちらか一方ではなく両方**を使います。役割が異なります。

### 6. 静的解析

| ツール | 用途 |
|--------|------|
| `terraform fmt -check` | フォーマット |
| `terraform validate` | HCL 構文・型 |
| `tflint` | Azure 固有の誤り（存在しない SKU 等） |
| `checkov` | CIS / WAF ベースのセキュリティ |
| `conftest` | **自社ポリシー**の強制 |

### 7. ドリフト検知

毎日 JST 06:00 に `plan -detailed-exitcode` を実行し、差分があれば Issue を自動起票します。

> ⚠️ ノイズ対策: Azure 側が自動付与するタグ等で誤検知が出る場合は `lifecycle { ignore_changes = [...] }` で除外してください。放置するとアラート疲れで誰も見なくなります。

---

## トラブルシューティング

| 症状 | 原因 | 対処 |
|---|---|---|
| `AADSTS70021` | `sub` クレームに対応する Federated Credential が無い | `environment:` 用の資格情報を追加 |
| `Error acquiring the state lock` | 別ジョブが実行中 / 前回が異常終了 | `concurrency` を設定。残留時のみ `force-unlock` |
| `Backend initialization required` | `-backend-config` の値が前回と異なる | `terraform init -reconfigure` |
| plan は成功、apply で権限エラー | apply ジョブの SP に書き込み権限が無い | RBAC ロールを確認 |
| `.terraform.lock.hcl` の差分 | ロックファイルが未コミット | **必ずコミットする** |
| PR コメントが投稿されない | 権限不足 | `permissions: pull-requests: write` |

---

## クリーンアップ

```bash
./scripts/teardown-oidc.sh --app-name terraform-cicd-oidc --resource-group rg-avm-demo
```
