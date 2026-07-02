# TODO

- [ ] ESLアプリ実装 [spec](docs/specs/app-spec.md)
  - [ ] Phase 2: 単語帳（登録・翻訳・復習）
    - OCR結果のテキストをタップして単語登録（spec 3.2、`WordOccurrence.sourcePhoto` 設定）
    - 復習機能（フラッシュカード／間隔反復）
  - [ ] レッスンページにメモ機能を追加
  - [ ] Phase 3: 問題作成
  - [ ] シミュレータ/実機のGUI操作で撮影→OCR・翻訳フルフロー（クラス/レッスン作成→撮影→
        結果表示→失敗時の再試行）を動作確認する（ANTHROPIC_API_KEYは設定済みで、backend側の
        `/api/ocr-translate`実キー呼び出しはcurlで複数回成功確認済み。iOS側のGUI操作は
        シミュレータ/実機操作権限が無いこのセッションでは未確認）

- [ ] 管理画面のログ時間をシアトルのタイムゾーンにする

## デバックメニュー(On Setting)
  - 単語のAI生成物を全て削除