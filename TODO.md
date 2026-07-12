# TODO

- [ ] backend の正規化修正（word-tap-normalize-wrong-word）を本番（esl.chobi.me / g3plus-ops）へデプロイする
- [ ] クイズ生成: 音声不要形式（tc3/tc6）の保存データに audioText が混入している（AI が余計に返したものが素通し。TTS 事前生成の無駄コスト。needsAudioText=false の形式は validateAndConvert で audioText を捨てる検討。2026-07-11 の Phase 3 作業中に発見・フレーズ固有ではなく既存単語でも発生）
