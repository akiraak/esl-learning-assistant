# 作文機能（添削込み）（調査・設計プラン）

## 目的・背景

現状のアプリは「撮影 → OCR・翻訳」「単語帳」「問題作成」の3機能（[app-spec.md](../specs/app-spec.md) 3章）で、
学習者の**アウトプット（英作文）を支援する機能は存在しない**。読む・覚える・問題を解く（受容・再認）は
カバーしているが、自分で英文を書き、その添削を受ける（産出）フローが無い。

本タスクでは、ユーザーが英作文を書き、Claude API による添削フィードバックを受けられる
**作文機能**を追加する。作文機能はアプリ仕様には未記載の新規機能領域のため、実装に着手する前に
データモデル・バックエンド・UI の設計方針を確定することを本プランの主目的とする。
（成果物: 本プラン＋確定内容の `docs/specs/` 反映。コード実装は Phase 分割して別途着手。）

## 確定事項（2026-07-04 ユーザー指定）

当初 §設計方針 で暫定デフォルトを置いていた点は、以下のユーザー指定で確定した。

1. **アクセス方法**: ナビゲーションタブに「作文」タブを追加し、そこから機能にアクセスする
   （→ 軸1 = 独立エンティティ確定 / UI 配置 = 新規タブ確定）
2. **入力は英日2テキスト**: ①書いた英文 ②それに対応する日本語（英文の訳、または日本語での説明）
   の2つを入力させる。日本語は「学習者が伝えたかった意図」を AI に渡し、添削精度を上げるための入力
   （→ 軸2 = 自由作文。ただし「お題」ではなく「意図を表す日本語」を必須で添える構成）
3. **出力は修正英文＋日本語解説**: 英日両方を AI に渡し、修正後の英文と日本語の解説を返して画面表示する
   （→ 軸3 = 「修正英文＋日本語解説」で確定。細かな指摘リスト/スコアは将来拡張）
4. **送信前に何度でも編集可**: 作文（英文・日本語）は AI に投げる前に何回でも編集できる。
   添削後も再編集して再送信（再添削）できる

## 現状整理（流用できる既存パターン）

作文添削は「テキストを Claude に送り、structured output で結果を受け取り、サーバ保存＋通信ログを取る」
点で、既存の `word-info` 機能とほぼ同型。以下のパターンをそのまま踏襲できる。

### バックエンド（Claude API 中継）

- 構造化出力: `callStructured<T>(model, schema, content)`（`backend/src/ocrTranslate.ts`）
  - ⚠️ structured output は array の `minItems`/`maxItems` 非対応（400）。件数制約は description で指示する
  - 省略可能項目は `type: ["string","null"]` の **nullable + required** で確実に埋めさせる（`wordInfo.ts` 参照）
- 生成ロジック: `backend/src/wordInfo.ts` の `generateWordInfo` が雛形（プロンプト組み立て → `callStructured`）
- ルーティング: `backend/src/index.ts` の `app.post("/api/word-info", ...)` が雛形
  - 入力バリデーション → 保存済みチェック → 生成 → `upsert*` 保存 → `insert*Log` ログ → レスポンス
- モデル指定: `backend/src/config.ts`（例: `config.wordInfoModel`）に `writingFeedbackModel` を追加
- コスト算出: `estimateCostUsd(model, inputTokens, outputTokens)`（`pricing.ts`）
- 保存＋ログ: `backend/src/db.ts`（`getStoredWord`/`upsertStoredWord`/`insertWordInfoLog` 等）
- 管理画面（通信ログ表示）: `backend/src/admin.ts`（仕様書5.2章。各機能ごとにログ一覧を出している）

### iOS（バックエンド通信）

- 通信サービス: `RemoteWordInfoService`（`BackendAPI.post(path:body:)` → JSON デコード）が雛形
- structured 結果の Codable 受け皿: `Word.swift` 内 `WordAIInfo` と同型の埋め込み Codable を作る
  - ⚠️ SwiftData 埋め込み Codable の地雷に注意（後述「テスト方針」）

## 設計方針（暫定デフォルト＋論点）

以下3つの決定軸について、**暫定デフォルト**（まず最小構成で出す方針）を置く。
各軸の選択肢は論点として残し、着手前にユーザー確認で確定する（→ §未確定事項）。

### 軸1: 作文データの紐づけ先 ／ 暫定=「独立エンティティ」

| 選択肢 | 内容 | 備考 |
|---|---|---|
| (a) 独立エンティティ ★暫定 | `Word` と同様に `Lesson` に従属しない `Composition` を新設。専用タブ or 単語帳の隣で一覧・履歴管理 | 自由に書き溜められる。マイグレーション影響が単語帳並みに小さい |
| (b) レッスンに紐づく | `Photo`/`Question` と同様 `Lesson` 配下のコンテンツにする | 授業ごとの作文課題向き。レッスン外で書けない |
| (c) 両方（任意リンク） | 独立エンティティ＋ `lesson: Lesson?` の任意参照 | 柔軟だが UI・実装が増える。将来 (a) から拡張可能 |

- 暫定 (a) の理由: アウトプット練習はレッスンに紐づかない自主学習の性格が強く、単語帳と同じ「独立して
  書き溜める」モデルが自然。将来 (c) への拡張（`lesson?` の任意追加）は nullable リレーションのため低リスク。

### 軸2: お題（プロンプト）の扱い ／ 暫定=「自由作文のみ」

| 選択肢 | 内容 | 備考 |
|---|---|---|
| (a) 自由作文のみ ★暫定 | ユーザーがテーマ・本文を自由に書く。お題フィールドは任意メモ扱い | 最小構成で最速に出せる |
| (b) AI がお題を提示 | Claude がレベル/単語帳を元にトピック文を生成。`/api/writing-prompt` を別途追加 | 書き始めのハードルが下がる。エンドポイントが1つ増える |
| (c) 単語帳の単語を使う課題 | 復習対象語を指定して使わせる。添削時に「指定語が使えているか」も評価 | 単語学習と連動。仕様が複雑化 |

- 暫定 (a) の理由: まず「書く→添削」のコアループを確立する。(b)(c) はコアが動いてからの拡張とし、
  データモデルに任意の `topic: String?` だけ先に用意しておけば (b) への移行は容易。

### 軸3: 添削フィードバックの出力粒度 ／ 暫定=「フル」

| 選択肢 | 内容 |
|---|---|
| (a) フル ★暫定 | 修正後の英文＋指摘リスト（該当箇所・種別・母語説明）＋総評コメント（＋レベル目安） |
| (b) シンプル | 修正後の英文＋短い総評のみ |

- 暫定 (a) の理由: 学習効果は「なぜ直したか」の説明にあり、`word-info` と同じく structured output で
  リッチに返すコストは小さい。UI 側で表示を段階開示すれば情報過多も避けられる。

## データモデル案（確定事項ベース）

`Lesson` に従属しない独立エンティティ `Composition` を新設（[data-model.md](../specs/data-model.md) §5 `Word` に倣う）。

```
Composition                                   (Lessonに従属しない独立エンティティ)
├─ id: UUID
├─ englishText: String                        (ユーザーが書いた英文)
├─ japaneseText: String                       (①の英文に対応する日本語＝訳 or 日本語での説明。意図)
├─ createdAt: Date
├─ updatedAt: Date                            (下書き編集のたびに更新)
├─ explanationLanguage: String                (解説言語。実質 "ja"。ユーザー母語設定を記録)
└─ feedback: WritingFeedback?                  (埋め込み Codable。未添削 or 編集後で無効化時は nil)
    ├─ correctedText: String                  (修正後の英文)
    ├─ explanation: String                    (日本語の解説)
    ├─ model: String                          (生成モデル)
    └─ generatedAt: Date
```

- 入力は **englishText / japaneseText の2フィールド必須**。日本語は「伝えたかった意図」を AI に渡し、
  英文だけでは曖昧な添削方向を確定させる用途（例: 誤って逆の意味に書いていても意図に沿って直せる）
- 「何度でも編集可」: `englishText`/`japaneseText` はいつでも編集でき、編集したら `updatedAt` を更新。
  既存 `feedback` は「その時点の英文への添削」なので、本文編集後は**古い添削として扱う**
  （UI で「本文が変更されています・再添削してください」を出す。実装は `feedback.generatedAt < updatedAt`
  で判定、もしくは編集時に `feedback = nil` にクリアのいずれか。前者=履歴が残る方を推奨）
- `feedback` は埋め込み Codable（`Word.reviewState` / `WordAIInfo` と同じ持ち方）→ **SwiftData の
  ライトウェイトマイグレーション不要**でフィールド追加できる（ただし §テスト方針の地雷回避が前提）
- v1 は最新1件の添削のみ保持（`feedback` 単数）。将来、指摘リスト/スコアや添削履歴が必要になったら
  `WritingFeedback` にフィールド追加 or `feedback: [WritingFeedback]` へ拡張（`data-model.md` §9 と同方針）

## バックエンド案

新規エンドポイント `POST /api/writing-feedback`（`word-info` の実装をテンプレにする）。

- リクエスト: `{ englishText: string, japaneseText: string, explanationLanguage?: string }`
  - `explanationLanguage` 省略時はユーザー母語（実質 "ja"）を既定にする
  - キャッシュ/保存はしない（作文本文は毎回異なりキャッシュが効かない）→ 常に生成。`regenerate` は不要
- 処理: バリデーション（英文・日本語とも必須／空・超過長チェック）→ `generateWritingFeedback()`
  → ログ（`insertWritingFeedbackLog`）→ 返却
- structured output スキーマ（`WRITING_FEEDBACK_SCHEMA`）:
  - `correctedText`（string, required）… 修正後の英文（全文）
  - `explanation`（string, required）… 日本語（= explanationLanguage）の解説。どこをなぜ直したかを含める
- プロンプト方針: 「学習者が書いた英文」と「伝えたかった意図（日本語）」の両方を渡し、意図に沿って
  自然な英文へ直し、修正点を日本語で解説させる
- モデル: `config.writingFeedbackModel` を追加（`config.ts`）
- コスト・ログ: `estimateCostUsd` ＋ `insertWritingFeedbackLog`（`db.ts` に追加）。管理画面（`admin.ts`）に
  作文添削ログの一覧を追加（仕様書5.2章の通信ログ表示要件）
- 保存: 作文本文は端末ローカルが原則（仕様書4章）。作文は毎回本文が異なりキャッシュが効かないため
  **サーバ側は保存せずログ用途のみ**とし、結果本体の永続化は iOS 側 `Composition.feedback` に置く

## UI 案（確定事項ベース）

- **ナビゲーションタブに「作文」を追加**（`ContentView` のタブ構成に1つ追加）。タブから機能にアクセス
- 一覧: `Composition` の一覧（新しい順）。FAB / ＋ボタンで新規作成（`WordsView` の追加動線を参考）
- 作成/編集画面（下書き）:
  - **英文** の入力欄と、**対応する日本語（訳 or 説明）** の入力欄の2つ（`LessonMemoEditView` のテキスト編集を参考）
  - 両方入力されるまで「添削する」ボタンは無効。**送信前は何度でも編集可**（都度 `updatedAt` 更新）
- 添削中: ローディング表示（`RemoteWordInfoService` 呼び出し中と同じ非同期パターン）
- 結果表示: **修正後の英文**（元英文との差分を強調できると理想）＋**日本語の解説**を画面に表示。
  修正英文の語を `TappableEnglishText` で単語帳登録に繋げられると学習動線が閉じる（任意・Phase 4）
- 再編集・再添削・削除: 本文を編集したら既存添削を「古い」と示し、再添削ボタンで作り直す
  （`WordDetailView` の delete/regenerate を参考）

## Phase 分割（実装着手時）

- **Phase 0: 設計確定**（本プラン）… 3軸の確定、`docs/specs/` への反映、実装タスクの切り出し
- **Phase 1: バックエンド**… `/api/writing-feedback`＋`writingFeedback.ts`＋`config`＋`db` ログ＋`admin` ログ表示
- **Phase 2: iOS データモデル＋通信**… `Composition`/`WritingFeedback`/`WritingIssue` モデル、
  `RemoteWritingFeedbackService`、Codable 受け皿
- **Phase 3: iOS UI**… 一覧・エディタ・添削結果表示・再添削/削除・タブ配置
- **Phase 4: 仕上げ**… 空状態/エラー処理、（任意）単語帳への指摘語登録動線、仕様書更新

## 影響範囲

- 調査・設計フェーズ（本タスク）: ドキュメントのみ（本プラン＋ `docs/specs/app-spec.md`・`data-model.md`）
- 実装時の想定影響先:
  - backend: `src/index.ts`（ルート追加）/ 新規 `src/writingFeedback.ts` / `src/config.ts` /
    `src/db.ts`（保存/ログ）/ `src/admin.ts`（ログ表示）/ `src/pricing.ts`（新モデルの価格があれば）
  - iOS: 新規 `Models/Composition.swift` / 新規 `Services/RemoteWritingFeedbackService.swift` /
    新規 Views（一覧・エディタ・結果）/ `ContentView.swift`（タブ追加時）/ `ESLLearningAssistantApp.swift`
    （SwiftData スキーマに `Composition` 登録）
  - specs: `app-spec.md`（3章に作文機能を追記、7章フェーズ）/ `data-model.md`（`Composition` 追加）

## テスト方針

- 本タスク（調査・設計）はドキュメント成果物のためテストコードなし
- 実装 Phase（特に Phase 2）で SwiftData の互換性を検証する。⚠️ 既知の地雷（メモリ参照）:
  - 非オプショナルの新規プロパティ追加でストアが開けなくなる → 追加は必ず **nullable ストレージ＋
    computed 既定値**で（[[swiftdata-codable-migration-pitfall]]）
  - 埋め込み Codable の CodingKeys リネームで値が黙って未永続化 → キー名は実プロパティ名と一致させる
    （[[swiftdata-codable-codingkeys-pitfall]]）
  - 既存ストアに `Composition` エンティティを追加して既存ストアが開けること（in-memory / 実機）を確認
- backend は `/api/writing-feedback` の入力バリデーション（空文字・超過長・型不正）と、structured output が
  スキーマ通り返ることを実際に叩いて確認

## 未確定事項（残課題）

主要な設計軸は §確定事項（2026-07-04）で確定済み。残るのは実装細部で、実装 Phase で詰める。

1. 本文編集後の既存添削の扱い: 「古い」と示して残す（`generatedAt < updatedAt` 判定）か、編集時に
   `feedback = nil` でクリアするか（→ 前者=履歴保持を推奨。Phase 2/3 で確定）
2. タブアイコン・並び順（`ContentView` の既存タブとの並び）
3. 修正英文の差分ハイライト表示の実装方法（Phase 3。まずはプレーン表示で可）
4. 単語帳への連携（修正英文の語をタップ登録）を v1 に含めるか（→ Phase 4 の任意項目）
