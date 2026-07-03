# TODO

- [ ] 単語を覚える問題機能を設計する [plan](docs/plans/word-memorization-quiz.md)
  - 記憶は１日後３日後７日後と間を伸ばしてテストすると覚えやすいと聞いたけどそれは確かか？
    - → 調査済み: 間隔を空けたテスト形式の復習自体は科学的に頑健。「広げる vs 等間隔」の差は小さく、固定拡張ステップで実用上十分（詳細はプラン §2）
  - [x] 音声入力を使った問題作成がどのようにできるか調査をする
    - → 調査済み: 発話回答型（単語を言い当てる）はオンデバイス音声認識で無料実装可。発音の採点は汎用ASRでは原理的に不可で Azure Pronunciation Assessment が本命。LLMに音声を直接採点させるのは精度不安定（詳細はプラン §7）
  - [ ] Phase 1: 設計確定・スペック更新（data-model.md の WordReviewState/Question 位置づけ）
  - [ ] Phase 2: ReviewScheduler・FormatSelector（比率調整） + WordReviewState 拡張 + ユニットテスト
  - [ ] Phase 3: ReviewSessionView（確定した出題形式）と Words タブの「今日の復習」導線
  - [ ] Phase 4: WordDetailView への復習状態表示・仕上げ

- [ ] 英文の単語をタップすると単語一覧に追加できるようにする