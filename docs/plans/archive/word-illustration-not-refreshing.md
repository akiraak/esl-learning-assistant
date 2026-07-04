# 単語イラストが生成完了後も「生成中」のまま表示されないバグの修正

## 目的・背景

TODO: 「単語追加時すぐ単語詳細を表示すると画像が生成中になるけど生成が終わっても表示されない」

### 調査結果（生成開始タイミングの答え）

- 画像生成は**単語追加時ではなく、単語詳細画面でイラスト行が表示された瞬間**に開始される
  - 単語追加時（`WordAddView.addWord()`）は AI 単語情報（訳語・語義・例文）の生成のみ開始
  - AI 情報が completed になると詳細画面に Illustration セクションが現れ、
    `WordIllustrationRow` の `.onAppear` で `POST /api/word-illustration` を呼ぶ
- バックエンドはジョブ方式ではなく同期方式（生成完了まで待って PNG を返す。最大 120 秒 × 3 リトライ）

### バグの原因（`ios/.../Views/WordDetailView.swift` の `WordIllustrationRow`）

1. **再描画トリガーの欠如**: `body` は「ローカルファイルの存在チェック」だけで分岐し、
   `@State isGenerating` を一度も読んでいない。SwiftUI は body 内で読まれた状態しか
   依存として追跡しないため、生成完了時の `isGenerating = false` では再描画が起きず、
   ファイルが保存されてもスピナーのまま残る（画面を開き直すと表示される）
2. **MainActor 外での @State 書き込み**: `generate()` は非分離メソッドで、その中の
   `Task {}` はグローバルエグゼキュータで実行される。`isGenerating` / `errorMessage`
   への書き込みがメインスレッド外で行われている（`TTSButton.generate()` も同パターン）
3. **タイムアウト不整合**: iOS 側 URLRequest の既定タイムアウトは 60 秒だが、
   バックエンドの画像生成は 60 秒を超えうる。超えた場合サーバ側は完成して保存するのに
   iOS 側だけ失敗し「生成は終わっているのに表示されない」のもう一つのルートになる

## 対応方針

1. `WordIllustrationRow` を「表示画像を `@State private var image: UIImage?` に保持し、
   body はそれを読む」形に作り直す
   - 行の表示時（`.task`、MainActor 継承）にローカルファイルを読み込み、無ければ
     サーバ生成 → ローカル保存 → `image` 更新。Retry も同じ関数を呼ぶ
   - 状態書き込みはすべて MainActor 上で行う
2. `BackendAPI.post` に任意の `timeout` パラメータを追加し、イラスト取得は 180 秒を指定する
3. `TTSButton.generate()` の `Task {}` を `Task { @MainActor in ... }` にして同パターンの
   潜在バグを解消する

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/WordDetailView.swift`（WordIllustrationRow / TTSButton）
- `ios/ESLLearningAssistant/Sources/Services/BackendAPI.swift`（timeout パラメータ追加）
- `ios/ESLLearningAssistant/Sources/Services/RemoteWordIllustrationService.swift`（timeout 指定）
- バックエンドは変更なし。`ReviewSessionView` のイラスト表示は既存ファイルの表示のみで対象外

## テスト方針

- iOS アプリをシミュレータ向けにビルドしてコンパイルを確認する
- 既存ユニットテストを実行してリグレッションがないことを確認する
- 実機での再現確認（単語追加 → 即詳細表示 → 生成完了で画像に切り替わる）はユーザーに依頼する
