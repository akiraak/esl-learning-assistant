# TODO

- [ ] PDF文字起こし・翻訳で HTTP 524（Cloudflareタイムアウト）が発生する問題の調査・対策 [plan](docs/plans/pdf-extract-translate-524-timeout.md)
  - [x] Phase 1: 原因確定（13ページスキャンPDFで159秒/152秒→524。加えて出力16384トークン上限でJSON切断しサーバー側でも失敗）
  - [x] Phase 2 Step 1: スキャンPDFのページ分割OCR（pdf-lib分割＋並列OCR、backend）
  - [x] Phase 2 Step 2: 非同期ジョブAPI（POST/GET /api/document-extract-translate/jobs、backend）
  - [x] Phase 2 Step 3: iOSのポーリング対応（RemoteDocumentExtractTranslateService）
  - [ ] Phase 2 Step 4: テスト・検証 — 単体テスト・ジョブAPI疎通・13ページ分割確認まで完了。
        残り: Claude 込みの完走確認（ローカル backend/.env の ANTHROPIC_API_KEY が無効で保留。
        キー更新 or 本番デプロイ後に実施）→ 完了したら本タスクを DONE.md へ、プランを archive へ
