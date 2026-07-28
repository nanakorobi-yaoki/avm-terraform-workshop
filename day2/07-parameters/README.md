# Demo 07 — パラメータ受け渡しの再設計

> Session 1 でいただいたご質問「エンドユーザー様へパッケージを納品する際、パラメータ Excel を同梱する必要がある。もっと良い方法はないか？」への回答デモです。

## 中心となる考え方 — Excel の「向き」を逆にする

| | 従来 | 提案 |
|---|---|---|
| Excel の役割 | **入力**（人が書く） | **成果物**（機械が出す） |
| 正となる情報源 | Excel | `params/*.yaml` |
| 転記作業 | 人手（ミスの温床） | なし |
| 実態との乖離 | 発生する | 原理的に発生しない |
| レビュー | 目視 | Pull Request の差分 |
| 入力チェック | Excel の入力規則（壊れやすい） | JSON Schema + `check` ブロック |

**Excel を無くすのではありません。** 納品物としての Excel はそのまま残し、それを「手で書くもの」から「自動で出るもの」に変えます。

---

## ファイル構成

```
07-parameters/
├── main.tf                          # yamldecode でパラメータを読み込む
├── params/
│   ├── contoso-prod.yaml            # ★ お客様が編集するのはここだけ
│   └── contoso-dev.yaml
├── schema/
│   └── params.schema.json           # 入力規則の定義（Excel の入力規則に相当）
└── tools/
    └── gen_param_sheet.py           # 納品用 Excel の自動生成
```

---

## デモ手順

### ① VS Code で YAML を開く — 入力体験を見せる

`params/contoso-prod.yaml` の 1 行目に注目してください。

```yaml
# yaml-language-server: $schema=../schema/params.schema.json
```

この 1 行で、YAML 拡張機能が以下を提供します。

- `location:` と打つと `japaneast` / `japanwest` … が**プルダウンで出る**
- `costCenter` に `abc` と入れると**即座に赤波線**
- 項目にカーソルを合わせると**説明がツールチップ表示**

> **見せ方**: `location: japaneast` を `japan-east` に書き換えて赤波線が出るところを見せます。Excel の入力規則と同じ体験が、Git 管理下で実現できていることが伝わります。

### ② CI での検証 — 壊れた値は plan にすら到達しない

```bash
pip install check-jsonschema
check-jsonschema --schemafile schema/params.schema.json params/*.yaml
```

意図的に壊した場合の出力例:

```
params/contoso-prod.yaml::$.costCenter: 'abc' does not match '^[0-9]{4}-[0-9]{4}$'
```

### ③ Terraform 側の整合性チェック

`main.tf` の `check` ブロックは、Schema では表現しきれない**業務ルール**を検証します。

```hcl
assert {
  condition     = var.env != "prod" || local.p.enablePrivateEndpoint
  error_message = "本番環境では enablePrivateEndpoint を true にしてください。"
}
```

> **見せ方**: `contoso-prod.yaml` の `enablePrivateEndpoint` を `false` にして `terraform plan` を実行し、日本語のエラーメッセージで止まることを見せます。

### ④ 差分レビュー — Excel には絶対にできないこと

```bash
git diff params/contoso-dev.yaml params/contoso-prod.yaml
```

dev と prod の違いが**行単位で明確**に出ます。これを PR にすれば、そのままレビュー記録・承認記録になります（ISMS の変更管理証跡としても有効）。

### ⑤ 納品用 Excel の自動生成

```bash
pip install openpyxl pyyaml

terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json

python tools/gen_param_sheet.py \
  --params params/contoso-prod.yaml \
  --schema schema/params.schema.json \
  --plan   tfplan.json \
  --output dist/contoso-prod-パラメータシート.xlsx
```

生成される Excel:

| シート | 内容 |
|---|---|
| パラメータ一覧 | 設定値 + Schema 由来の項目名・説明・制約 |
| リソース一覧 | `plan` から抽出した「実際に作られるリソース」 |

**重要**: 説明文や制約は Schema から自動で拾っています。Schema を直せばドキュメントも自動で追従し、二重管理が消えます。

---

## CI への組み込み

```yaml
- name: パラメータ検証
  run: |
    pip install check-jsonschema
    check-jsonschema --schemafile schema/params.schema.json params/*.yaml

- name: 納品パラメータシート生成
  if: github.ref == 'refs/heads/main'
  run: |
    pip install openpyxl pyyaml
    python tools/gen_param_sheet.py \
      --params params/${{ matrix.customer }}-${{ matrix.env }}.yaml \
      --schema schema/params.schema.json \
      --plan   tfplan.json \
      --output dist/${{ matrix.customer }}-${{ matrix.env }}.xlsx

- uses: actions/upload-artifact@v4
  with:
    name: parameter-sheets
    path: dist/*.xlsx
```

**成果**: main にマージされた瞬間、納品用パラメータシートが Actions のアーティファクトとして生成されます。担当者が Excel を作る作業そのものが消えます。

---

## 段階的な移行

いきなり全部を変える必要はありません。

| Step | やること | 効果 |
|---|---|---|
| 1 | `optional()` + `validation` でパラメータ数を減らす | 記入項目そのものが減る |
| 2 | 残ったパラメータを YAML + JSON Schema に移す | 検証とレビューが自動化 |
| 3 | Excel を自動生成に切り替える | 転記作業と乖離が消滅 |

Step 1 だけでも効果があります。**「そもそも聞かなくてよい項目」を AVM のセキュア既定値に任せる**のが最も効きます。

---

## 補足: それでも Excel 入力を残したい場合

お客様の運用上どうしても Excel での入力が必要な場合は、**Excel → YAML の一方向変換**に限定してください。

```
Excel ──(変換スクリプト)──> YAML ──> Terraform
```

> ⚠️ **双方向同期は絶対に作らないでください。** どちらが正なのか分からなくなり、コンフリクト解決の仕組みを自作する羽目になります。変換は必ず一方向、YAML を SSOT とします。
