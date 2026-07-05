# 作文の反復改善（ラウンド式の履歴スレッド）

## 目的・背景

作文機能（英作文の添削）は現状「英文＋日本語意図」を送ると添削（修正英文＋解説）が1件返る
**単発モデル**で、本文を編集すると既存添削が「古い」になり `feedback` を上書きするだけ。
学習者が一度の添削で終わらず、**添削を踏まえて書き直し → 再添削 → さらに改善**という
反復を回せるようにしたい。

ユーザー確定の方針（AskUserQuestion）:
- **ラウンド式の履歴スレッド**: 「英文＋日本語」を送るたびに1ラウンドとして積み上げ、
  過去の全ラウンド（英文・修正・解説）を AI に渡して文脈を踏まえて添削する。画面に履歴が縦に並ぶ。
- **各ラウンドの入力欄は自分の英文を維持**: 添削後もエディタは学習者が書いた英文のまま。
  修正英文の自動投入はしない（学習者が自分で手直しして再送する）。

## 対応方針

### データモデル（iOS: `Composition.swift`）

- 埋め込み Codable `WritingRound { id, englishText, japaneseText, feedback: WritingFeedback, createdAt }`
  を新設（1回分の提出＝英文＋意図＋その添削）。
- `Composition` に nullable ストレージ `roundsStorage: [WritingRound]?` を追加し、computed `rounds`
  で既定 `[]`。**マイグレーション安全のため必ず optional 追加**
  （memory: swiftdata-codable-migration-pitfall）。CodingKeys は付けない
  （memory: swiftdata-codable-codingkeys-pitfall）。
- 旧データ互換: `roundsStorage` が空でも `feedback != nil` なら getter が
  「englishText/japaneseText + feedback を Round 1」として見せる（破壊的マイグレーション不要）。
  既存 `feedback` フィールドは削除せず残す（getter は storage 優先なので二重計上しない）。
- 派生: `latestFeedback`, `hasFeedback`, `draftMatchesLastRound`（下書きが最終ラウンドと同一か）。
- `englishText/japaneseText` は「現在の下書き（次に送るラウンド）」として維持。`updatedAt` は編集で更新。
- `isFeedbackStale` は撤去し、バッジ判定は `hasFeedback`/`draftMatchesLastRound` ベースへ。

### バックエンド（`writingFeedback.ts` / `index.ts`）

- `generateWritingFeedback(english, japanese, lang, history)` に `history: WritingFeedbackRound[]`
  （`{ englishText, japaneseText, correctedText, explanation }`）を追加。history があれば
  「複数回書き直して改善中。前回から改善した点は前向きに触れ、残る問題を指摘」旨をプロンプトに前置きし、
  過去ラウンドを列挙する。history 空なら従来の単発プロンプト。
- `/api/writing-feedback` で `history` を任意受理・防御的に検証（配列でなければ []、直近 N=20 件に丸め、
  各フィールドを長さ上限でクランプ）。通信ログ（`writing_feedback_requests`）は現行のまま（今回ラウンドの
  英日を記録）で DB スキーマ変更はしない。

### iOS 通信層（`RemoteWritingFeedbackService.swift`）

- `fetchFeedback(..., history: [WritingFeedbackRoundPayload])` を追加し RequestBody に `history` を積む。

### iOS UI（`CompositionDetailView.swift`）

- 上部にラウンド履歴（古い順）を Section で縦に並べる: 「Round N」見出し＋Your English／Corrected
  （単語タップ登録に接続）／Explanation（Markdown）。
- その下に下書きエディタ（英文・日本語）＋ Review/Re-review ボタン＋削除。
- `canReview` = 英日とも非空 **かつ** 下書きが最終ラウンドと相違（同一なら送る意味が無いので無効）。
- 送信成功で `rounds` に新ラウンドを追記。エディタは自分の英文を維持（クリアしない）。
- `CompositionsView` のバッジ: 未添削／編集中（下書きに未送信の変更あり）／添削済み。

### 仕様書

- `data-model.md §9`: `feedback` 単数 → `rounds` 履歴へ。`WritingRound` 追加、旧データ互換方針を明記。
- `app-spec.md §3.4`: ラウンド式の反復改善フローを追記。

## 影響範囲

- iOS: `Composition.swift`, `CompositionDetailView.swift`, `CompositionsView.swift`,
  `RemoteWritingFeedbackService.swift`（＋各 #Preview）
- backend: `writingFeedback.ts`, `index.ts`
- specs: `data-model.md`, `app-spec.md`
- 新規 @Model エンティティは無し（`WritingRound` は値型属性なので ModelContainer 登録は不要）

## テスト方針

- backend: `history` 有無での疎通（過去ラウンドを踏まえた添削・改善への言及）を実 API で確認。
- iOS: ビルド＋既存 `CompositionUITests`（下書きフロー・Review 活性・空作文破棄）がグリーンであること。
  反復（ラウンド追加）は実通信を伴うためオフライン UI テスト対象外。
- マイグレーション: 旧 `feedback` のみを持つ既存作文が Round 1 として表示されることを Preview/手動で確認。
