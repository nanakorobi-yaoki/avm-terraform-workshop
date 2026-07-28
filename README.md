# AVM Terraform VBD Workshop

Azure Verified Modules (AVM) × Terraform — 2日間ハンズオンワークショップ（各日 2.5 時間）

---

## 📅 Day 1 — Terraform 基礎 Deep Dive（2.5 時間）

| 時間 | 区分 | 内容 |
|------|------|------|
| 0:00–0:10 | 導入 | オープニング／目的・到達目標 |
| 0:10–1:10 | 座学 | IaC 入門、Terraform コアワークフロー（init / plan / apply）、構成基礎（HCL・変数・tfvars・ローカル値・出力）、変数の優先順位、sensitive 変数、複合型（object / tuple / optional） |
| 1:10–1:20 | 休憩 | — |
| 1:20–2:20 | デモ | リソース作成 + lifecycle メタ引数 + Provider エイリアス + 状態ファイル確認 → 変数 Deep Dive（sensitive・複合型・precedence）→ AVM Databricks Workspace デプロイ |
| 2:20–2:30 | まとめ | Day1 まとめ ＆ Q&A |

## 📅 Day 2 — モジュール・状態・CI/CD・AVM（2.5 時間）

| 時間 | 区分 | 内容 |
|------|------|------|
| 0:00–0:05 | 導入 | Day1 振り返り／本日の進め方 |
| 0:05–0:35 | 座学① | 依存関係・モジュール、状態管理（Azure Blob リモート状態）、CI/CD（OIDC・GitHub Actions / Azure DevOps・静的解析・Policy as Code） |
| 0:35–1:05 | 座学②（AVM） | 3分類（Resource / Pattern / Utility）、「Verified」の意味・WAF セキュア既定値、一貫したインターフェース、Terraform Registry・命名規則、セマンティックバージョニング |
| 1:05–1:15 | 休憩 | — |
| 1:15–2:20 | デモ | モジュール／リモート状態 → CI/CD パイプライン → AVM 参照（version 固定）→ 一貫インターフェース実演 → マルチティア構成 → AVM from scratch |
| 2:20–2:30 | まとめ | 全体まとめ・次のステップ（AI支援IaC） |

---

## 📁 プロジェクト構成

```
AVM_Terraform_Workshop/
├── day1/
│   ├── 01-resource-creation/       # 基本リソース作成 + lifecycle + Provider alias + 状態ファイル確認
│   ├── 02-variables-locals-outputs/ # 変数 Deep Dive（sensitive・複合型・precedence）
│   └── 03-avm-databricks/          # AVM Databricks Workspace デプロイ（実践 AVM 体験）
├── day2/
│   ├── 01-modules/                 # モジュール作成・利用デモ
│   ├── 02-remote-state/            # Azure Blob リモート状態デモ
│   ├── 03-cicd/                    # GitHub Actions & Azure DevOps パイプライン
│   ├── 04-avm-reference/           # AVM モジュール参照（version 固定）
│   ├── 05-avm-consistent-interface/ # 一貫インターフェース実演
│   └── 06-multi-tier-avm/          # マルチティア構成 & AVM from scratch
└── README.md
```

## 前提条件

- Azure サブスクリプション
- Terraform >= 1.9
- Azure CLI (`az login` 済み)
- Git
- VS Code + HashiCorp Terraform 拡張機能
