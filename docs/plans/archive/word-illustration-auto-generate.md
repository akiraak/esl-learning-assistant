# 単語詳細のイラストをバックグラウンドで生成して終わったら表示する

## 目的・背景

単語詳細の Illustration セクションは現在、手動の「Generate Illustration」ボタン →
スピナー → 表示という流れで、ユーザーが押さない限りイラストが生成されない。
これを、詳細画面を開いたら自動でバックグラウンド生成を開始し、完了したら表示に
切り替わるようにする（単語AI情報の自動生成と同じ UX）。

## 対応方針

`WordDetailView.swift` の `WordIllustrationRow` を変更する:

- ローカル保存済み: 即表示（現状どおり）
- 未生成: 行の表示（onAppear）と同時に自動で生成開始し、スピナー
  「Generating illustration…」を表示。完了したら画像表示に切り替わる
- 失敗: エラーメッセージ + Retry ボタン（単語AI情報の failed 表示と同じパターン）
- 手動の「Generate Illustration」ボタンは廃止

前提条件の整理:
- Illustration セクションは `word.aiInfoStatus == .completed` のときだけ描画されるため、
  素材となる単語情報が無い状態で自動生成が走ることはない
- サーバ側は生成済みならキャッシュ返却（/api/word-illustration）なので、
  再訪時のコスト増はない。生成画像は端末ローカルにも保存され、以降はローカル表示
- `wordIllustrationGenerateButton` を参照するテストは無い（grep 確認済み）

## 影響範囲

- `ios/.../Views/WordDetailView.swift` の `WordIllustrationRow` のみ

## テスト方針

- ローカル backend + シミュレータで単語詳細を開き、ボタン操作なしで
  スピナー → イラスト表示に切り替わることを確認する
- 到達不能なバックエンド指定時にエラー + Retry が出ることをコード上で確認
  （AI情報が completed かつ ネットワーク断のケース）
