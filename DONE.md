# DONE

- [x] アプリの仕様を決める (2026-06-30)
- [x] iPhoneアプリ スケルトン作成 [plan](docs/plans/archive/ios-app-skeleton.md) (2026-06-30)
- [x] データ構造資料の作成（Lesson / Photo / Word / Question / QuizResult 等のスキーマ、spec 9章対応） [spec](docs/specs/data-model.md) (2026-06-30)
- [x] データ構造を元に画面レイアウトのアイデア出し（ワイヤーフレーム検討、spec 9章対応） [spec](docs/specs/screen-design.md) [plan](docs/plans/archive/screen-layout-ideas.md) (2026-06-30)
- [x] 日常フロー（Lesson追加→写真アップロード→単語追加→問題を解く）中心に画面構成を見直す [spec](docs/specs/screen-design.md) [plan](docs/plans/archive/daily-flow-screen-redesign.md) (2026-06-30)
- [x] iOS画面実装: クラス追加・レッスン追加・撮影→OCR・翻訳（SwiftDataモデル、モックOCR・翻訳サービス） [plan](docs/plans/archive/ios-class-lesson-capture-screens.md) (2026-06-30)
- [x] 実機ビルド・インストール用シェルスクリプト作成（run-ios-device.sh、無線接続のAkiraのiPhoneで動作確認済み） [plan](docs/plans/archive/device-build-install-script.md) (2026-06-30)
- [x] バックエンド実装・Claude API連携（Node.js/TypeScript + Express + SQLite、モデルはclaude-sonnet-5、
      構造化出力でOCR・翻訳結果を取得、通信ログ・画像・トークン数・コストを記録する管理画面/adminを実装。
      iOS側もモックからRemoteOCRTranslationServiceへ置き換え、失敗時の再試行ボタン・
      SettingsのサーバーURL設定・ATS例外を追加） [plan](docs/plans/archive/backend-claude-api-integration.md) (2026-06-30)
- [x] ローカルバックエンド起動用スクリプト作成（run-server.sh、.env未設定時のエラー・
      npm install/build/start を一括実行することを確認済み） [plan](docs/plans/archive/local-server-start-script.md) (2026-06-30)
- [x] 撮影済み（未翻訳）写真の翻訳機能（PhotoDetailViewでpending状態の写真は自動でOCR・翻訳を
      開始し、processing/failed状態には手動再試行ボタンを表示。completed状態にも「再翻訳する」
      ボタンを追加し、バックエンド実装前のMockOCRTranslationServiceによる固定文（サンプル文）が
      保存されたままの既存写真も再翻訳できるようにした。HomeViewのレッスン写真一覧にも
      未翻訳写真をまとめて翻訳するボタンを追加） [plan](docs/plans/archive/translate-pending-photos.md) (2026-06-30)
- [x] 実機ビルド時にバックエンドURLをMacのIPへ自動設定（Info.plistにBackendBaseURLキーを追加し
      ビルド設定 BACKEND_BASE_URL 経由で注入、AppSettingsKeysはInfo.plistから既定値を読むよう変更。
      run-ios-device.shがMacのLAN IPを自動検出してビルド時に埋め込むため、実機でのサーバーURL
      手動設定が不要になった） [plan](docs/plans/archive/device-backend-url-autodetect.md) (2026-06-30)
- [x] バックエンドのログ出力強化（backend/src/logger.tsを新設し標準出力とbackend/data/server.log
      の両方にタイムスタンプ付きで出力。全リクエストのロギングミドルウェア、
      ocr-translateの開始・成功・失敗ログ、uncaughtException/unhandledRejectionの
      捕捉を追加） [plan](docs/plans/archive/backend-console-logging.md) (2026-06-30)
- [x] run-server.shに既存ポート占有プロセスの停止機能を追加（.envのPORTを読み取り、
      lsofでLISTEN中のPIDを検出してkill、応答が無ければkill -9で強制終了してから
      起動するように変更。ダミープロセスで自動停止・正常起動を確認済み） [plan](docs/plans/archive/run-server-kill-existing-port.md) (2026-06-30)
- [x] OCR・翻訳結果のMarkdown化とadmin表示の整形（Claude APIへのプロンプト・出力スキーマで
      ocrText/translatedTextをMarkdown形式にするよう指示。adminはmarkedパッケージでMarkdown→HTML
      変換し、`&`/`<`/`>`エスケープ後にパースすることでHTMLタグ注入を防止、見やすいCSSを追加。
      iOS側もAttributedString(markdown:)経由の表示に変更し、生の#や**が見えないようにした） [plan](docs/plans/archive/markdown-ocr-translation.md) (2026-06-30)
- [x] 管理画面UI改善: 一覧＋詳細ページ方式に変更しOCR結果を読みやすくした（`/admin`はID・日時・
      縮小画像・状態などのみのコンパクトな表にし、`/admin/logs/:id`に詳細ページを新設。大きめの
      画像（クリックで原寸表示）とOCR結果・翻訳結果の全文をスクロールなしの折り返し表示にし、
      前後のログへのナビゲーションと存在しないIDの404表示も実装。curlで一覧・詳細・404・
      前後ナビ（欠番IDのスキップ含む）の各表示を確認済み） [plan](docs/plans/archive/admin-log-detail-page.md) (2026-07-01)
- [x] 翻訳ステップを別モデル（Haiku最新版）に変更できるようにした（OCRと翻訳を2回の独立した
      Claude API呼び出しに分割し、OCRは`ANTHROPIC_MODEL`（既定claude-sonnet-5）、翻訳は
      `ANTHROPIC_TRANSLATE_MODEL`（既定claude-haiku-4-5）で別々のモデルを使えるように設定化。
      DBの`requests`テーブルもocr_model/translate_modelとトークン数を別々に記録するようリネーム・
      追加し、既存DBへの後方互換マイグレーション（ALTER TABLE RENAME/ADD COLUMN）も実装。
      adminの一覧・詳細ページもOCR/翻訳モデルを別行表示。実画像を`/api/ocr-translate`に投げ、
      OCRがSonnet・翻訳がHaikuで実行されコストが合算記録されることを確認済み
      （haikuモデルがoutput_configのeffortパラメータ非対応だったため翻訳側のみ除去して対応）） [plan](docs/plans/archive/translate-model-selection.md) (2026-07-01)
- [x] コスト計算式をOCR分・翻訳分・合計に分けた（`requests`テーブルに`ocr_cost_usd`/`translate_cost_usd`
      列を追加（`cost_usd`は合計のまま維持）、既存DBへのALTER TABLE ADD COLUMNマイグレーションも実装。
      adminの一覧・詳細ページでOCR分/翻訳分/合計の3値を表示。実画像で確認しOCR $0.02066 + 翻訳
      $0.00287 = 合計 $0.02354 のように内訳と合計が一致することを確認済み） [plan](docs/plans/archive/split-ocr-translate-cost.md) (2026-07-01)
- [x] OCRモデルと翻訳モデルが同じ場合は1回の統合呼び出しに、異なる場合は2回の呼び出しに
      分岐するようにした（`ocrTranslate.ts`に共通の構造化出力呼び出しヘルパー`callStructured`を
      新設し、`config.ocrModel === config.translateModel`なら画像→ocrText/translatedText同時取得の
      1回呼び出し、異なれば従来のOCR→翻訳の2回呼び出しに分岐。haiku系モデルは`output_config.effort`
      非対応なため呼び出し側で自動的に省略。adminでは統合呼び出し時に翻訳欄を「OCR呼び出しに統合
      （追加コストなし）」と表示し誤解を防止。実画像でOCR=翻訳=Sonnet 5（統合・1回呼び出し）と
      OCR=Sonnet/翻訳=Haiku（分割・2回呼び出し）の両方を確認済み） [plan](docs/plans/archive/combined-call-when-same-model.md) (2026-07-01)
