# 管理画面: AI利用料金（コスト集計）ページの作成

## 目的・背景

各AI機能の1件あたりのコストは既に各ログ/保存テーブルの `cost_usd` に記録され、
各一覧ページでも「直近100件のコスト合計」までは見えている。しかし
**機能横断で「どの機能・どのモデルにいくら使ったか」「今月/今日いくらか」を
俯瞰できる画面が無い**ため、全体の利用料金を把握するにはページを渡り歩くか
DBを直接集計するしかない。

管理画面に利用料金（spend）の集計ページを追加し、全機能のコストを
**キャリア（OpenAI / Gemini / Claude）別・機能別・モデル別・期間別**に
一覧できるようにする。

なお既存の `/admin/pricing`（ナビ「AI料金」）は**単価表**であり別物。
本ページは**実利用額の集計**なので、ナビ上も別項目・別ラベルで追加する。

## データソース（既存・スキーマ変更なし）

`cost_usd` を持つ7テーブルを集計対象とする（`backend/src/db.ts`）。

| 機能 | テーブル | 時刻列 | モデル列 | 種別 |
|---|---|---|---|---|
| OCR・翻訳 | `requests` | `created_at` | `ocr_model` / `translate_model` | 追記ログ |
| 単語情報 | `word_info_requests` | `created_at` | `model` | 追記ログ（`cache_hit` 有） |
| 作文添削 | `writing_feedback_requests` | `created_at` | `model` | 追記ログ |
| 音声文字起こし・翻訳 | `transcription_requests` | `created_at` | `transcription_model` / `translate_model` | 追記ログ |
| TTS音声 | `tts_audio` | `created_at` | `model` | 保存キャッシュ（1音声1行・upsertで上書き） |
| 単語イラスト | `word_illustrations` | `created_at` | `model` | 保存キャッシュ（1枚1行・upsertで上書き） |
| 単語クイズ | `quiz_questions` | `created_at` | `model` | 保存（variant単位・再生成で置換） |

### キャリア（プロバイダ）判定

モデルIDからキャリアを判定する。対応は `backend/src/pricing.ts` の単価テーブル所属で確定できる。

| キャリア | モデル（単価テーブル） | 使う機能 |
|---|---|---|
| **Claude**（Anthropic）| `DEFAULT_PRICING`: `claude-sonnet-5` / `claude-opus-4-8` / `claude-haiku-4-5` | OCR・翻訳・単語情報・作文添削・クイズ |
| **Gemini**（Google）| `DEFAULT_TTS_PRICING`: `gemini-2.5-*-tts` ＋ `DEFAULT_TRANSCRIPTION_PRICING`: `gemini-2.5-flash` | TTS・音声文字起こし |
| **OpenAI** | `DEFAULT_IMAGE_PRICING`: `gpt-image-2` | 単語イラスト |

- 判定は「どの `DEFAULT_*` テーブルに属すか」を第一とし、未知モデルはIDの接頭辞
  （`claude-`→Claude / `gemini-`→Gemini / `gpt-`・`dall-e-`→OpenAI）でフォールバック判定する。
  それでも不明なら「その他」に寄せる（将来モデル追加時も落ちないように）。
- クイズの `model = "rule"`（イラスト系のルール生成・**AI不使用でコスト0**）は
  いずれのキャリアにも属さない扱い（「AI不使用」／コスト0）とし、キャリア別合計を歪めない。
- 実装は `pricing.ts` に `providerForModel(model): "openai" | "gemini" | "claude" | "other"`
  を追加してエクスポートし、db.ts / admin.ts から共用する（キャリア知識の単一ソース）。

### 集計上の注意（画面にも注記する）

- **追記ログ4種**（requests / word_info / writing_feedback / transcription）は
  呼び出しごとの真の履歴なので累計コストとして正確。
- **保存キャッシュ3種**（tts_audio / word_illustrations / quiz_questions）は
  「現在保持している成果物の最終生成コスト」であり、再生成・削除の履歴は残らない。
  よって総額はこれら機能について**下限の近似**になる旨を画面に明記する。
  （真の累計を出すなら append-only なコストイベント表が必要。今回は対象外＝将来拡張候補。）
- タイムスタンプは全て UTC の ISO 文字列。「今日/今月」判定と日次集計は
  既存の `formatSeattleTime` と同じ America/Los_Angeles で行う（tz境界のズレを防ぐため
  日付バケツは SQL ではなく JS 側で `sv-SE` フォーマッタを使って算出する）。

## 対応方針

### Phase 1: キャリア判定 + 集計ヘルパを追加

**Phase 1a: `backend/src/pricing.ts` に `providerForModel` を追加**

- `providerForModel(model: string): "openai" | "gemini" | "claude" | "other"` を実装・エクスポート。
  判定はまず `DEFAULT_PRICING`／`DEFAULT_TTS_PRICING`＋`DEFAULT_TRANSCRIPTION_PRICING`／
  `DEFAULT_IMAGE_PRICING` の所属、次にID接頭辞フォールバック（上表のとおり）。
- 表示名 `providerLabel(provider)`（"OpenAI" / "Gemini" / "Claude" / "その他"）も併置。

**Phase 1b: `backend/src/db.ts` に集計ヘルパを追加**

機能横断の集計を返す関数を追加する（SQLでの単純集計 + JSでのtz日付バケツ）。

- 各テーブルの「コスト付きイベント」を
  `{ feature, model, provider, createdAt, costUsd, inputTokens, outputTokens }`
  の共通形に正規化して取り出すヘルパ群（provider は `providerForModel` で付与。
  OCR・翻訳と文字起こしは ocr/translate を2イベントに分解し、
  combined call（`ocr_model===translate_model` かつ translate側0トークン）は
  重複計上しないよう1イベント扱いにする ＝ 既存 `isCombinedCall` と同じ判定）。
- そこから:
  - `getUsageCostSummary()`: 全期間・当月・当日の総額（Seattle tz基準）
  - `listUsageCostByProvider()`: **キャリア別（OpenAI/Gemini/Claude/その他）の
    コスト計（降順）/ 件数 / 構成比**
  - `listUsageCostByFeature()`: 機能別の 件数 / in・out トークン計 / コスト計 / 直近利用日時
    （各行にキャリアも表示）
  - `listUsageCostByModel()`: モデル別の コスト計（降順）/ キャリア / 件数
  - `listDailyUsageCost(days)`: 直近N日（既定30日, Seattle tz日付）の日次コスト
    （簡易バーで推移が見えるようにする）
- 件数は個人利用規模なので全行取得→JS集計で問題ない（tts等が増えたら
  期間フィルタ付きSQLへ寄せる、と注記）。

### Phase 2: `backend/src/admin.ts` に利用料金ページを追加

- `NavSection` に `"usage"` を追加し、`NAV_ITEMS` に
  `["usage", "/admin/usage", "利用料金"]` を追加（「AI料金」＝単価 の直後）。
- `adminRouter.get("/usage", ...)` を追加し、既存の `renderPage` / `.stats` / `.card`
  テーブルの定型で構成する:
  - サマリーカード: 総コスト / 当月コスト / 当日コスト /（任意）総イベント数
  - **キャリア別テーブル（または3カード）: OpenAI / Gemini / Claude のコストと構成比**
    （降順・「その他」は該当時のみ表示）。ページ上部に置き最初に目に入るようにする。
  - 機能別テーブル: 機能名（既存ログページへリンク）/ キャリア / 件数 / in・out トークン /
    コスト / 構成比 / 直近利用。金額は既存同様 `$x.toFixed` 表示。
  - モデル別テーブル: モデル / キャリア / コスト（降順）/ 件数 / 構成比。
  - 日次推移: 直近30日の日次コスト（CSSの簡易横棒で可視化）。
  - キャッシュ系3機能が近似である旨の注記（`.page-sub` か小さな注意書き）。
- 集計は Phase 1 のヘルパ呼び出しのみ。新規の外部通信・書き込みは無し（読み取り専用）。

### Phase 3: 目視確認

- `npm run build` → サーバ再起動 → `/admin/usage` を実データで確認。
  - サマリー3種の金額、機能別・モデル別の合計が各ログページの「コスト合計」と整合するか
  - 当月/当日が Seattle tz で正しく切り替わるか（境界時刻のデータで確認）
  - ナビの「利用料金」がアクティブ表示になるか、「AI料金」（単価）と混同しないか

## 影響範囲

- `backend/src/pricing.ts`（`providerForModel` / `providerLabel` 追加のみ）
- `backend/src/db.ts`（集計ヘルパ追加のみ・スキーマ変更なし）
- `backend/src/admin.ts`（NavSection / NAV_ITEMS / `/admin/usage` ルート追加のみ）
- 既存ページ・iOS への影響なし。読み取り専用で副作用なし。

## テスト方針

- `npm run build` が通ること。
- ローカルサーバで `/admin/usage` を実データ目視（Phase 3 の観点）。
- 機能別コスト合計 ＝ 各既存ログページのコスト合計（直近件数の差はあるが全期間で整合）を突き合わせ。

## 未決事項 / 確認ポイント

- ナビ命名: 新規「利用料金」/ 既存「AI料金」（単価）の2本立てで進める想定。
  紛らわしければ既存を「AI単価」へリネームする案もあり（要判断・既定は現状維持）。
- 期間フィルタ（当月のみ表示 等のUI切替）は初版では入れず、まず全期間＋当月/当日サマリ
  ＋日次推移で提供する（必要になれば拡張）。
