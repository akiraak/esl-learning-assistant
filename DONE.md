# DONE

- [x] 同じクラスに同名のレッスンを作れないようにする（`LessonAddView`に重複チェックを追加。
      トリム後のレッスン名がクラス内の既存レッスンと大文字小文字を区別せず一致する場合は
      「追加」ボタンを無効化し、フッターに赤字で理由を表示。UIテストに重複ブロックの
      検証ケースを追加しシミュレータで確認済み）
      [plan](docs/plans/archive/unique-lesson-title-per-class.md) (2026-07-01)
- [x] 単語一覧の検索・レッスン単語タップでのタブ切替（単語タブに`.searchable`で見出し語・
      訳語の部分一致検索を追加、ヒット0件時は`ContentUnavailableView.search`表示。
      タブ間遷移用の`AppRouter`（`@Observable`）を新設し、レッスンタブの単語をタップすると
      Wordsタブへ切り替わって単語詳細を表示するように変更。UIテストにタブ切替・検索の
      検証を追加しシミュレータで確認済み）
      [plan](docs/plans/archive/word-search-and-tab-switch.md) (2026-07-01)
- [x] Lesson画面の作り直し（レイアウト案4つを作成し案A ヘッダーカード型を採用。選択中の
      クラス名＋レッスン名をリスト先頭のカードで常時表示しタップで切り替えシート。クラス/
      レッスンの作成はアラート入力をやめ、シートから遷移する専用フォーム画面（ClassAddView/
      LessonAddView）に分離。レッスン作成後はシートごと閉じてレッスン画面へ。「写真」
      セクションは「コンテンツ」に改名。コンテンツ・単語・問題の表示はレッスン単位。
      UIテストを新フローに追随させシミュレータで確認済み）
      [plan](docs/plans/archive/lesson-screen-redesign.md) (2026-07-01)
- [x] タブバーの表示名を英語化（Lessons / Words / Settings。画面内の文言は日本語のまま。
      UIテストも追随し、シミュレータで表示・単語追加フローを再確認済み）
      [plan](docs/plans/archive/tab-labels-english.md) (2026-07-01)
- [x] 画面レイアウト3タブ化（レッスン/単語/設定）。ホームタブをレッスンタブに改名し、
      単語・問題セクションを追加。問題タブは廃止（レッスンタブへ統合予定）。単語タブを新規実装
      （Word/WordOccurrenceのSwiftDataモデル追加、一覧・詳細・追加（レッスン任意指定）・
      スワイプ削除、同一見出し語は出現記録のみ追加）。project.ymlにswift-markdown-uiの
      packages定義を追加しxcodegen再生成で消えないようにした。シミュレータのUIテスト
      （3タブ表示・単語追加フロー）で動作確認済み
      [plan](docs/plans/archive/tab-navigation-redesign.md) (2026-07-01)
- [x] iOS: OCR・翻訳本文中のMarkdown見出し（`#`〜`###`）に背景色付きラベルを適用し、
      地の文と見分けやすくする（`markdownBlockStyle`でレベルごとに背景色の濃さ・フォントサイズを変更）
      [plan](docs/plans/archive/ios-markdown-heading-background.md) (2026-06-30)
- [x] iOS: OCR結果・翻訳結果のMarkdownを見出し・箇条書きが分かるように表示する
      （最初はPresentationIntentベースの自前`MarkdownContentView`を実装したが、
      テーブル・コードブロック等への将来対応も見据えてSPM依存の`swift-markdown-ui`
      （`Markdown(_:)`）に置き換え）
      [plan](docs/plans/archive/ios-markdown-block-rendering.md)
      [plan](docs/plans/archive/ios-markdownui-adoption.md) (2026-06-30)
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
- [x] OCR結果（英語）のTTS読み上げ機能（`SpeechService`（AVSpeechSynthesizerラッパー）を新設し、
      `PhotoDetailView`のOCR結果セクションに再生/停止ボタンを追加。Markdown記号を読み上げないよう
      プレーンテキスト化してから発話、画面遷移時は自動停止。バックエンド・SwiftDataモデルの変更なし。
      xcodebuildでのシミュレータ向けビルド成功を確認済み（実機での音声再生確認は未実施）） [plan](docs/plans/archive/tts-ocr-text-playback.md) (2026-06-30)
- [x] Gemini TTS版の音声読み上げ（声のタイプ選択つき）（backend/src/tts.tsを新設し`POST /api/tts`を追加。
      声のタイプ（ちょビ=Leda / なるこ=Aoede、スタイル文言含む）は~/Projects/claude-code-manager/の
      voice-persona.jsonの設定を移植。iOS側は設定画面に「音声エンジン: 端末内蔵/Gemini」
      「声のタイプ: ちょビ/なるこ」のPickerを追加し、GeminiSpeechService（AVAudioPlayerで
      バックエンドから受け取ったWAVを再生）を新設。PhotoDetailViewの再生ボタンはボタン1つのまま
      設定に応じて端末内蔵/Gemini TTSを切り替える。バックエンドはtsc、iOSはxcodebuildでの
      ビルド成功を確認済み（GEMINI_API_KEYの設定・実機での動作確認はユーザー側で実施）） [plan](docs/plans/archive/gemini-tts-voice-selection.md) (2026-06-30)
- [x] Gemini TTSのスタイル指示を日本語→英語に修正（読み上げるOCR本文は英語なのにスタイル指示だけ
      日本語だったため発音が日本語寄りになっていた不具合。ちょビ/なるこのスタイル文言を英訳し、
      curlで生成した音声をafplayで実際に聴いて改善を確認済み） (2026-07-01)
- [x] Gemini TTSモデル（Flash/Pro）の選択機能（`gemini-2.5-flash-preview-tts`（高速）と
      `gemini-2.5-pro-preview-tts`（高品質）をMODEL_PRESETSとして追加し、`POST /api/tts`の
      リクエストで`model`を指定可能に。環境変数`GEMINI_TTS_MODEL`はリクエスト単位選択に統一する
      ため廃止。iOS設定画面に「TTSモデル: 高速/高品質」Pickerを追加。バックエンドはtsc、iOSは
      xcodebuildでのビルド成功、curlでflash/pro両方の200応答と不正値の400拒否を確認済み） [plan](docs/plans/archive/gemini-tts-model-selection.md) (2026-07-01)
