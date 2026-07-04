# TODO


- [ ] 英文の単語をタップすると単語一覧に追加できるようにする
- [ ] 単語 fall を追加すると単語一覧「秋」になり「落ちる」だと分からない。複数意味がある場合の対応（辞書式に意味クラスタごとに別エントリへ分割） [plan](docs/plans/dictionary-style-word-split.md)
  - [x] Phase 1: コア分割（AI グループ判定・`senseGroupKey`・分割生成・一覧の複数行表示・イラスト語義ごと）
  - [ ] Phase 2: クイズの語義分離（quiz_questions キー＋API に判別子）
  - [ ] Phase 3: 既存データの遡及分割（Regenerate で分割）
