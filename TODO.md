# TODO

- [ ] backend の正規化修正（word-tap-normalize-wrong-word）を本番（esl.chobi.me / g3plus-ops）へデプロイする
- [ ] UIテスト `testClassLessonCaptureFlow` を現行環境に合わせて修正する
  - レッスンカレンダー化の作業前（main のクリーン状態）から同一箇所で失敗している既存問題
  - iOS 26 の PHPicker は確定がナビバーの「追加/Add」ではなく右上の ✓ ボタンに変更されている
  - さらに現行フローは写真追加後に写真詳細へ自動遷移しないため、最後の
    「OCR Result (English)」表示の検証手順自体の見直しが必要（詳細を開く手順の追加など）
- [ ] クイズ生成: 音声不要形式（tc3/tc6）の保存データに audioText が混入している（AI が余計に返したものが素通し。TTS 事前生成の無駄コスト。needsAudioText=false の形式は validateAndConvert で audioText を捨てる検討。2026-07-11 の Phase 3 作業中に発見・フレーズ固有ではなく既存単語でも発生）
