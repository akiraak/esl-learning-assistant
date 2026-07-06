# TODO

- [ ] レッスン詳細のコンテンツに複数タイプのコンテンツをまとめる [plan](docs/plans/lesson-content-multi-type.md)
  - コンテンツタイプ
    - 既存の写真と翻訳
    - Audio
    - YouTubeへのリンク
  - 追加ボタンでタイプを選択する画面を１枚挟む
  - YouTube は動画ID（またはURL）を指定して追加（API キー・バックエンド不要）
  - [x] Phase 1: `YouTubeLink` モデル基盤（モデル/リレーション/videoID抽出パーサ/コンテナ登録・マイグレーション確認）
  - [x] Phase 2: YouTube の追加・表示・再生（YouTubeAddView 動画ID/URL入力のみ・タイトル入力なし / YouTubeRow / YouTubeDetailView / 共通 YouTubeThumbnail）
  - [ ] Phase 3: コンテンツ統合表示（写真＋Audio＋YouTube を1リストにまとめ、Audioセクション廃止）
  - [ ] Phase 4: タイプ選択の追加フロー（AddContentTypeView ＋ ルーティング）
  - [ ] Phase 5（任意）: 仕上げ（サムネイル/文言）
