# DONE

- [x] レッスン画面の Add Photo / Add Word をセクションヘッダー（`Content (XXX)` / `Words (XXX)`）
      右端のシンプルな「+」ボタンに移動（独立した追加行を削除。識別子は
      `lessonPhotoAddButton` 新設 / `lessonWordAddButton` 維持、UIテストの参照も更新）
      [plan](docs/plans/archive/lesson-section-header-add-buttons.md)（2026-07-02）

- [x] backend 公開デプロイ対応（g3plus + Docker + esl.chobi.me）。backend の `/api/*` に
      `X-API-Secret` ヘッダ認証を追加（timing-safe 比較、未設定なら起動 fail-fast、
      2026-07-01 本番デプロイ済み）し、iOS アプリを対応させた:
      `AppSettingsKeys.apiSecret`（UserDefaults + Info.plist デフォルトの既存パターン、
      ハードコードなし）、Settings 画面に API Secret 入力欄、/api/* 3サービスの
      リクエスト生成を `Services/BackendAPI.swift` に共通化してヘッダ付与、
      401 は「Check the API Secret in Settings」と分かるメッセージを表示
      （`Photo.processingErrorMessage` / `Word.aiInfoErrorMessage` に保存、TTS は alert）。
      デフォルト base URL を本番 `https://esl.chobi.me` に切替し、`run-ios-device.sh` は
      `--local`（Mac IP + backend/.env の secret 注入、デフォルト）/ `--prod`
      （本番 URL + gitignore 済み `.env.prod` の secret 注入）で切り替え可能に。
      接続問題の切り分け用に BackendAPI の os.Logger ログ、Settings の Test Connection
      （/health 疎通 + 認証必須 `GET /api/ping` で secret 一致確認）、backend の
      `/api/ping` を追加。実機 + 本番サーバで OCR翻訳 / 単語情報 / TTS のフルフロー動作確認済み。
      デプロイ設定（Dockerfile / docker-compose / .env）は g3plus-ops リポジトリ側で管理
      （運用手順: g3plus-ops の docs/workflows/esl-learning-assistant.md）。
      本番 secret は Sx360 の `g3plus-ops/esl-learning-assistant/.env`、ローカルは
      `backend/.env` に必須（未設定だと backend が起動しない）
      [plan](docs/plans/archive/public-deploy-api-secret.md) /
      [plan](docs/plans/archive/ios-api-secret-header.md) /
      [plan](docs/plans/archive/backend-api-logging.md) (2026-07-02)

- [x] Lessonページの Wordsに単語追加ボタン。タップでWordsタブの追加画面に遷移させLessonは
      設定されて変更できない状態にする（`AppRouter` に `pendingAddWordLesson` と
      `showAddWord(for:)` を追加し、既存の `pendingWord` と同じ「routerに積んでWordsタブ側が
      消費する」方式でタブ横断遷移を実装。`WordAddView` に `fixedLesson` 引数を追加し、
      固定時は Picker の代わりに固定表示行（クラス名 / レッスン名）とし変更不可に。
      `LessonsView` の Words セクション先頭に Add Word ボタンを追加。UIテスト
      （レッスンから追加→固定表示確認→追加後のレッスンWords反映→Wordsタブ通常追加の
      Picker回帰確認、スクリーンショット付き）を追加しシミュレータで全成功）
      [plan](docs/plans/archive/lesson-words-add-button.md) (2026-07-01)

- [x] レッスンページにメモ機能を追加（`Lesson` に `memo: String?` を追加（オプショナルのため
      ライトウェイトマイグレーションで自動移行）。`LessonsView` の Words と Questions の間に
      Memo セクションを追加し、タップで新設の `LessonMemoEditView`（TextEditor）へ遷移。
      空白のみで保存した場合は nil に戻して「メモなし」扱い。autosave任せだと保存直後の
      アプリ終了でメモが失われることを実機動作確認で発見したため、保存時に明示的に
      `modelContext.save()` を実行。ユニットテスト3件・UIテスト（作成→空白保存→複数行保存→
      再起動後の永続化確認、スクリーンショット付き）を追加し全成功）
      [plan](docs/plans/archive/lesson-memo.md) (2026-07-01)
- [x] クラス名とレッスン名を編集可能に（`ClassEditView` / `LessonEditView` を新設し、
      クラス・レッスン切り替えシートに編集導線を追加（クラスはセクションヘッダー、
      レッスンは各行右端の鉛筆アイコン）。レッスン名は追加時と同じ大文字小文字を区別しない
      同名重複チェックを編集対象自身を除外して適用。SwiftDataのautosaveで永続化、
      バックエンド変更なし。シミュレータ向けビルド成功・ユニットテスト10件全成功を確認済み）
      [plan](docs/plans/archive/edit-class-lesson-names.md) (2026-07-01)
- [x] 各タブ画面トップのナビゲーションタイトル（Lessons / Words / Settings）を削除
      （`LessonsView` / `WordsView` / `SettingsView` の `.navigationTitle` を削除。
      シミュレータ向けビルド成功を確認済み）
      [plan](docs/plans/archive/remove-tab-page-nav-titles.md) (2026-07-01)
- [x] 単語詳細の Meanings / Collocations / Synonyms & Antonyms も読み上げ可能に
      （各語義の英英定義、各コロケーション行、Synonyms/Antonyms のカンマ区切りリスト全体に
      `SpeechButton` を追加。シミュレータ向けビルド成功を確認済み）
      [plan](docs/plans/archive/word-detail-speech-more-sections.md) (2026-07-01)
- [x] 単語詳細の英文部分に読み上げを追加（iOS組み込みTTS。既存`SpeechService`
      （AVSpeechSynthesizer）を再利用し、`WordDetailView`のPronunciation（見出し語）・
      AI例文（Examples）・レガシー例文（Example Sentence）の各行末にスピーカーボタンを
      追加。再生中は停止ボタンに切り替わり、同じボタン再タップで停止・別ボタンで切り替え、
      画面離脱時に自動停止。シミュレータ向けビルド成功を確認済み）
      [plan](docs/plans/archive/word-detail-speech.md) (2026-07-01)

- [x] 単語追加ダイアログの簡素化＋UI表記の全英語化（`WordAddView`を見出し語＋レッスン選択のみに
      変更（訳語・例文・品詞の入力を削除）。訳語はAI生成完了時に先頭語義の母語訳で自動補完し、
      ユーザー入力済みの訳語は上書きしない。一覧・詳細は訳語が空の間は表示しない。全ビューの
      ユーザー可視文字列を英語化（AI生成コンテンツ＝母語の学習情報とコードコメントは対象外。
      声のタイプはChobi/Narukoにローマ字化）。見出し語フィールドに`wordTextField`識別子を付与し
      UIテストのプレースホルダー文字列依存を解消、UIテストの日本語参照を英語に追随（PHPicker等
      OS側UIは日英両対応）。`testClassLessonCaptureFlow`に前回データ残存時の全クリア前処理を追加。
      訳語自動補完のユニットテスト2件を追加しユニット13件・UIテスト8件全成功、シミュレータの
      スクリーンショットで英語表記・簡素化フォーム・訳語自動補完を確認済み）
      [plan](docs/plans/archive/word-add-simplify-and-english-ui.md) (2026-07-01)
- [x] 単語の情報をサーバのAIで生成しクライアントで表示（バックエンドに`POST /api/word-info`を
      新設し、`claude-haiku-4-5`のstructured outputで語義（母語訳＋英英定義）・発音・語形変化・
      例文・コロケーション・類義語/反意語・使用上の注意・CEFR・語源・使用域・よくある間違いを
      生成（structured outputはarrayのminItems/maxItems非対応のためdescriptionで件数指示）。
      SQLiteの`word_info_requests`テーブルにログを記録し、管理画面に一覧・詳細ページを追加。
      iOS側は`Word`に`aiInfo`(WordAIInfo)/`aiInfoStatus`等を追加（optional/デフォルトありの
      軽量マイグレーション）、`RemoteWordInfoService`＋`WordAIInfoGenerator`を新設し単語登録時に
      自動生成（教科書OCR本文があれば文脈として送信）。詳細画面にAI情報セクション（生成中/失敗時の
      再試行/再生成メニュー付き）、単語一覧に一括生成ボタンと行ステータスアイコンを追加。
      curlで文脈あり/なし・多義語("run")の語義文脈判定を確認、ユニットテスト6件・UIテスト
      （到達不能URLでの失敗ステータスUI）追加、シミュレータ実機フロー（登録→自動生成→表示）と
      管理画面ログ記録を確認済み）
      [plan](docs/plans/archive/word-ai-info-generation.md) (2026-07-01)
- [x] デバッグメニューのクラス削除をクラス指定式に変更（「クラスとそのレッスンの削除」
      ボタンでダイアログにクラス一覧（クラス名＋レッスン数）を表示し、選んだクラスだけ
      削除できるように変更。「すべてのクラスを削除」も選択可。`DebugDataCleaner.deleteClass`
      は対象クラス配下の写真ファイルだけを削除する。クラス0件時はボタン無効化。
      ユニットテスト（他クラス・単語が残ることを検証）とUIテスト（クラス指定削除で
      レッスンタブが空状態に戻る）で確認済み）
      [plan](docs/plans/archive/debug-delete-specific-class.md) (2026-07-01)
- [x] 設定タブにデバッグメニューを追加（Debugビルドのみ表示。データの全クリア／クラスと
      そのレッスンの全削除（単語帳は残す）／単語の全削除の3操作を`DebugDataCleaner`として
      実装し、各操作は確認ダイアログ付き。`PhotoStorage`に画像ファイル削除ヘルパーを追加。
      フッターに現在のデータ件数を表示。in-memoryコンテナのユニットテスト3件と
      UIテスト（ダイアログを閉じただけでは消えない／削除実行で消える）で確認済み。
      Releaseビルドではコンパイルアウトされることも確認済み）
      [plan](docs/plans/archive/settings-debug-menu.md) (2026-07-01)
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
