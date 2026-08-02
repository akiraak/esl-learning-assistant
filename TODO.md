# TODO

- [ ] 単語学習コンテンツの作成
- [ ] 管理画面の作文でスペルミスを強調表示 [plan](docs/plans/writing-spellcheck-highlight.md)
  - [ ] Phase 1: サーバ側のスペル判定（typo-js + spellcheck.ts + POST /admin/writing/:id/spellcheck）
  - [ ] Phase 2: 執筆画面のハイライト（紙の背後に backdrop を重ねて赤い波線）
  - [ ] Phase 3: 誤検出を潰す無視リスト（修正候補ポップオーバー＋辞書に追加）