# AI単語情報の生成完了後にイラスト生成を自動で開始する

## 目的・背景

現状、単語イラストの生成は「単語詳細画面でイラスト行が表示された瞬間」にしか始まらない
（docs/plans/archive/word-illustration-not-refreshing.md の調査結果）。
そのため単語を追加しただけではイラストは作られず、詳細を開いてから数十秒待たされる。

理想の流れ（ユーザー要望）:

1. 単語追加 → AI 単語情報（テキスト）の生成がバックグラウンドで走る（現状どおり）
2. テキスト生成が完了したら、**続けてイラスト生成も自動でバックグラウンド開始**する
   （詳細画面を開いていなくても走る）
3. アプリはテキスト生成が終わった直後に詳細を表示でき、イラストは生成中スピナー →
   出来次第自動で画像に差し替わる

## 対応方針

### 1. `WordIllustrationGenerator`（新規: `Sources/Support/WordIllustrationGenerator.swift`）

`WordAIInfoGenerator` と同様の画面から独立した共有インスタンス（`@MainActor` シングルトン）。
`ObservableObject` にして生成状態を画面へ配信する。

- `@Published inFlight: Set<String>`（キーは `WordIllustrationStore.key`）
- `@Published failures: [String: String]`（キー → エラーメッセージ）
- `generateIfNeeded(word:targetLanguage:)`: ローカル保存済み or 生成中なら何もしない。
  それ以外はサーバ生成 → ローカル保存。多重リクエストはキーで排他

### 2. `WordAIInfoGenerator.generate` の成功パスに連結

単語情報の反映直後に `WordIllustrationGenerator.shared.generateIfNeeded(...)` を呼ぶ。
targetLanguage は単語情報の生成に使ったものと同じ値（＝イラストのキャッシュキーと一致）。
イラストの失敗は単語情報の成功表示に影響させない（クイズ事前生成と同じ扱い）。

### 3. `WordIllustrationRow` を共有ジェネレータ監視型に変更

- `@ObservedObject generator = WordIllustrationGenerator.shared` を観測
- 表示分岐: 画像ロード済み → 画像 / 生成中（inFlight） → スピナー / 失敗 → エラー + Retry
- `.task(id: 生成中フラグ)` で、生成完了（inFlight から消えた）タイミングにローカル
  ファイルを読み込んで表示。未生成・未着手なら `generateIfNeeded` を呼ぶ
  （既存単語＝この変更前に AI 情報だけ生成済みの単語のフォールバックを兼ねる）
- Retry は失敗記録をクリアして `generateIfNeeded` を再実行

## 影響範囲

- 新規: `ios/ESLLearningAssistant/Sources/Support/WordIllustrationGenerator.swift`
  （xcodegen のため `xcodegen generate` で xcodeproj を再生成する）
- `ios/ESLLearningAssistant/Sources/Support/WordAIInfoGenerator.swift`（成功時の連結）
- `ios/ESLLearningAssistant/Sources/Views/WordDetailView.swift`（WordIllustrationRow）
- バックエンドは変更なし（POST /api/word-illustration はサーバキャッシュ付きなので
  二重呼び出しにも安全側。ReviewSessionView は既存ファイル表示のみで対象外）

## テスト方針

- シミュレータ向けビルド + 既存ユニットテスト全件
- 実機確認（ユーザー依頼）: 単語追加 → 詳細を開かず待つ → 詳細を開いたら最初から画像が
  出ること / 追加直後に詳細を開いた場合はテキスト表示 → スピナー → 画像差し替えの順に
  なること
