# DONE

- [x] 単語詳細に意味が直感的に分かりやすいようなイラストをAIで生成して表示する。
      OpenAI GPT Image 2（`gpt-image-2`、1024x1024/low）で第1義のイラストを生成する
      `POST /api/word-illustration` を追加（tts.ts パターン踏襲: raw fetch + リトライ、
      `word_illustrations` テーブル + `data/illustrations/<hash>.png` 保存、
      キー sha256("model|word|target_language|sense_index")、キャッシュヒット時は再生成なし）。
      料金は per-image 固定ではなくトークン単価制（in $5 / out $30 per 1M、手動固定値
      `DEFAULT_IMAGE_PRICING`）で usage から算出し `/admin/pricing` に表示。
      管理画面 `/admin/illustrations`（サムネイル一覧・再生成・削除）を追加。
      iOS は `WordIllustrationStore`（Application Support/illustrations、サーバと同一キー）+
      `RemoteWordIllustrationService` + 単語詳細 AI 情報の先頭に Illustration セクション
      （生成ボタン → スピナー → 表示、ローカルキャッシュ優先）。
      tsc / xcodebuild / ストア単体テスト4件 / curl（401・400・キー未設定500・
      キャッシュヒット・管理画面）確認済み。実画像生成は `OPENAI_API_KEY` 設定後に確認。
      [plan](docs/plans/archive/word-illustration-generation.md)（2026-07-03）

- [x] 管理画面にAIモデルの料金ページを作成。
      `/admin/pricing` を追加（サイドバー「AI料金」）。適用中の単価（per 1M・USD）を
      モデル / 用途（config から逆引き: OCR・翻訳・単語情報・TTS）/ 取得元
      （LiteLLM・Google公式ページ）付きで一覧し、既定値と異なる適用値は注意色 + 既定値併記。
      サマリーカード（登録モデル数・pricing_state の最終更新日時）、category=pricing の
      system_logs 直近10件の更新履歴、「今すぐ更新チェック」ボタン
      （POST /admin/pricing/refresh → LiteLLM と Google を即時チェック）を実装。
      実データで表示・更新ボタン（302 + system_logs 2行追加）を確認済み。
      [plan](docs/plans/archive/admin-pricing-page.md)（2026-07-03）

- [x] Gemini TTS 料金を DB 保存し定期更新に含める。
      LiteLLM の価格JSONは TTS モデルに誤値（flash $0.30/$2.50、公式は $0.50/$10.00）を載せて
      いるため、TTS だけは Google 公式料金ページ（?hl=en + Accept-Language: en で英語版固定、
      言語指定なしだと機械翻訳版がランダムに返る）を取得元にした。`STATIC_PRICING` を
      `DEFAULT_TTS_PRICING` に改名して currentPricing に統合し、`applyFetchedTtsPricing()`
      （タグ除去テキストから Input/Output price を抽出、既存と同じ10倍乖離ガード・失敗時現行値
      維持）を追加。起動時+24時間ごとに Claude（LiteLLM）→ TTS（Google）を直列チェックし、
      結果を system_logs に記録、`pricing_state` に全5モデル分を保存。
      ライブページ10回連続抽出成功・既存TTS行のコスト再計算一致($0.018592)を確認済み。
      [plan](docs/plans/archive/gemini-tts-pricing-sync.md)（2026-07-03）

- [x] 管理画面の表示をカッコ良く。デザイン例をいくつか作成して検証する。
      3案（クリーンライトSaaS風 / ダークオプス / サイドバーダッシュボード）のモックアップを
      作成して比較検証し、「案Bのダーク配色 × 案Cのサイドバーレイアウト」のハイブリッドを採用。
      `backend/src/admin.ts` を全面リスタイル: ダークテーマ（地#0C1116/アクセント#38BDF8）、
      左固定サイドバーナビ、一覧ページにサマリーカード（件数・コスト合計・エラー・平均処理時間等）、
      ステータスピル・カード化テーブル・モノスペース数字を導入。機能・ルーティングは変更なし。
      全7ページ（一覧5 + 詳細2）を実データ + headless Chrome スクリーンショットで目視確認済み。
      [plan](docs/plans/archive/admin-ui-design-refresh.md)（2026-07-03）

- [x] アプリ側音声生成に一時停止や早送りなど一般的な再生プレイヤーの機能を入れる。
      `TTSPlaybackService` を拡張（pause/resume/seek/±5秒スキップ/再生速度0.5〜1.5×/進捗タイマー、
      `play(data:)` 追加）し、共通操作パネル `TTSPlayerBar` を新規作成。
      WordDetailView / PhotoDetailView の `.safeAreaInset(edge: .bottom)` に配置し、
      再生中だけ画面下部に出てコンテンツを隠さない（画面を見ながら聞ける）。
      PhotoDetailView の `GeminiSpeechService` は音声取得専任にし再生を playback 側へ共通化。
      `TTSPlaybackServiceTests`（実WAV生成で pause/seek/クランプ/rate維持を検証）を追加、
      全24ユニットテスト成功・シミュレータビルド/起動確認済み。実機での操作感の確認は未実施。
      [plan](docs/plans/archive/tts-player-controls.md)（2026-07-03）

- [x] アプリSettingからSpeechEngineを削除。TTS Modelだけで選択できるように。
      `ttsEngine`（local/gemini）キーを廃止し `ttsModel` に統合（local / flash / pro の3択）。
      Settings の TTS Model ピッカーに On-Device / Gemini 2.5 Flash TTS / Gemini 2.5 Pro TTS を表示。
      Voice ピッカーは On-Device 選択時のみ無効化。OCR読み上げの分岐は `ttsModel != "local"` に変更。
      単語詳細のサーバTTSボタンは On-Device 選択時 flash に読み替えて送信（キャッシュキーも従来と互換）。
      旧 `ttsEngine` 設定はアプリ起動時に `ttsModel` へ一度だけ移行して削除。バックエンドは変更なし。
      シミュレータ向けビルドが通ることを確認済み
      [plan](docs/plans/archive/remove-speech-engine-setting.md)（2026-07-03）

- [x] 管理画面TTS一覧に音声の長さと生成料金を表示。
      長さはWAVフォーマット固定（24kHz/16bit/mono）を利用して `byte_size` から算出（既存行も表示可）。
      料金は Gemini レスポンスの `usageMetadata` からトークン数を取得しチャンク合算で
      `tts_audio` に記録（`input_tokens`/`output_tokens`/`cost_usd` 列を後方互換マイグレーションで追加）。
      単価は Google 公式（flash: $0.50/$10.00、pro: $1.00/$20.00 per 1M tokens）を確認して反映。
      LiteLLM の価格JSONはTTSモデルに通常テキストモデルの単価を載せており不正確なため、
      Gemini TTS は自動更新の対象外とし `pricing.ts` の固定テーブル（STATIC_PRICING）で持つ。
      新規合成でトークン・料金が記録されること、キャッシュヒットで二重計上されないこと、
      表示秒数が実際の音声長（afinfo実測3.13秒→表示0:03）と一致することを検証済み
      [plan](docs/plans/archive/tts-admin-duration-cost.md)（2026-07-02）

- [x] AI料金表の自動更新＋管理画面「システムログ」ページ。
      LiteLLMの価格JSON（model_prices_and_context_window.json）を起動時＋24時間ごとに取得し、
      検証ガード（正の数値・既定値から10倍以内）を通った単価だけ `pricing.ts` のメモリ上の
      単価表に反映（`DEFAULT_PRICING` はフォールバックとして温存、再起動時は `pricing_state` から復元）。
      チェック結果（成功／変更あり／失敗）は毎回 `system_logs`（汎用テーブル）に記録し、
      管理画面に「システムログ」ページを新設して表示。パスは既存の `/admin/logs/:id`（OCRログ詳細）
      との衝突を避け `/admin/system-logs` とした。取得失敗・値破損時も料金計算は従来値で継続する
      ことを検証済み [plan](docs/plans/archive/pricing-auto-update.md)（2026-07-02）

- [x] サーバ側でのTTS生成は長文でも可能か確認する。できなければ対応。
      実測の結果、8,000文字でも生成自体は可能だが、finishReason=OTHER / HTTP 500 の散発と、
      STOPなのに音声が途中で切れるサイレント打ち切り（4,000文字で観測）があり
      一括合成は実用に耐えないと判明。`tts.ts` に文境界チャンク分割（最大1,500文字）＋
      チャンク単位リトライ（打ち切り検知含む）＋3並列合成→PCM連結を実装し、
      `/api/tts` の上限を2,000→20,000文字に引き上げ。4,000文字で約310秒の
      正常な音声が約2.5分で生成できることを確認（検証: `backend/scripts/tts-long-check.ts`）
      [plan](docs/plans/archive/tts-long-text.md)（2026-07-02）

- [x] クラス名・レッスン名編集の保存も明示的に `modelContext.save()` する。
      `LessonEditView` / `ClassEditView` / `ClassAddView` / `LessonAddView` に加え、
      同一パターンだった `CaptureView`（写真insert直後とOCR処理完了後）にも
      `try? modelContext.save()` を追加。autosave任せだと保存直後の強制終了で
      変更が失われる問題への対応（メモ機能で確認済みのパターンを横展開）
      [plan](docs/plans/archive/explicit-modelcontext-save.md)（2026-07-02）

- [x] 管理画面のログ時間をシアトルのタイムゾーンにする。DB保存はUTC ISOのまま、
      `admin.ts` に `formatSeattleTime()`（Intl.DateTimeFormat, America/Los_Angeles,
      PST/PDT略称付き）を追加し、全9カ所のタイムスタンプ表示
      （OCRログ一覧/詳細・単語情報ログ一覧/詳細・単語一覧/詳細・TTS一覧）を変換表示に変更
      [plan](docs/plans/archive/admin-log-seattle-timezone.md)（2026-07-02）

- [x] TTSデータをサーバで保存する機能を入れる。backend に `tts_audio` テーブルと `data/tts/` を
      新設し、`/api/tts` は同一 (voice, model, text)（sha256キー）ならGemini再呼び出しなしで
      保存済みWAVを返す（ファイル欠損時は再合成して自己修復）。管理画面に「TTS一覧」タブを
      追加し、`<audio>` での試聴と削除（ファイルごと）が可能。iOS は単語詳細の
      Pronunciation（見出し語）/ Meanings / Examples の読み上げボタンをサーバTTSの
      「生成→スピナー→再生」ボタン（TTSButton）に置き換え。生成した音声は
      Application Support/tts/ に端末保存し、再訪時は最初から再生ボタンになる。
      失敗時は alert 表示。TTSAudioStore のユニットテスト3件を追加
      [plan](docs/plans/archive/tts-server-storage.md)（2026-07-02）

- [x] レッスン画面で単語を追加した直後にWordsセクションへ即時反映されない問題を修正。
      `WordAddView` が出現記録を to-one 側（occurrence.lesson）だけ設定して insert していたため、
      逆側 `lesson.wordOccurrences` への反映と変更通知が次の autosave まで遅れていた。
      lesson 側の配列にも明示的に append して即時発火させ、追加完了時に明示的な
      `modelContext.save()` も行うように変更（強制終了時のデータ保全の既知パターン）
      [plan](docs/plans/archive/lesson-words-immediate-refresh.md)（2026-07-02）

- [x] 単語データをサーバに保存。backend に `words` テーブルを新設し、`/api/word-info` は
      保存済みなら Claude API を呼ばずに返却（`cached: true`・コスト0でログ記録）、
      未保存 or `regenerate: true` なら生成して upsert 保存。キャッシュキーは
      (trim+小文字化した word, targetLanguage)。管理画面に「単語一覧」タブを追加し、
      詳細ページから削除・再生成が可能。iOS は `WordInfoService` に `regenerate` 引数を追加し、
      WordDetailView の「Regenerate AI Info」（生成済み上書き時）のみ `regenerate: true` を送る
      [plan](docs/plans/archive/word-info-server-storage.md)（2026-07-02）

- [x] レッスン画面から単語詳細を開いた場合も戻るときはレッスンに戻る。
      単語タップでWordsタブへ切り替えるのをやめ、レッスン画面のスタックに
      `WordDetailView` を直接プッシュするように変更（Back・削除後の pop ともレッスンに戻る）。
      不要になった `AppRouter.pendingWord` / `showWord` と `WordsView` 側の受け取り処理を削除し、
      `AppRouter` はタブ選択の保持のみに簡素化。UIテスト2件を新挙動に合わせて更新し、
      詳細から Back でレッスンに戻る検証を追加
      [plan](docs/plans/archive/lesson-word-detail-return-to-lesson.md)（2026-07-02）

- [x] レッスン画面で単語を追加した場合は戻るときはレッスンに戻る。
      追加ボタンでWordsタブへ切り替えるのをやめ、レッスン画面上で直接
      `WordAddView(fixedLesson:)` をシート表示するように変更（閉じればレッスンに戻る）。
      不要になった `AppRouter.pendingAddWordLesson` / `showAddWord` と
      `WordsView` 側の受け取り処理を削除し、UIテスト3件を新挙動に合わせて更新
      [plan](docs/plans/archive/lesson-word-add-return-to-lesson.md)（2026-07-02）

- [x] Wordsタブの右上「・・・」を削除。ツールバーの「+」と secondaryAction の
      「Generate Missing AI Info」（一括生成）を廃止し、追加ボタンは右下の
      フローティング「+」ボタンに変更（空状態では従来どおり中央の Add Word ボタン）。
      `wordAddButton` 識別子を維持して既存UIテストはそのまま通る
      [plan](docs/plans/archive/words-tab-fab-add-button.md)（2026-07-02）

- [x] LessonsとWordsタブの単語一覧を、見出し語と訳語の2行表示から1行表示に変更。
      横にはみ出す場合は末尾省略（訳語側から先に省略）
      [plan](docs/plans/archive/word-row-single-line.md)（2026-07-02）

- [x] Lesson画面Wordsの行頭削除ボタンをやめ、左スワイプの「Remove」に変更。
      挙動は変わらず、そのレッスンとのリンク（`WordOccurrence`）を外すのみで
      Wordsタブの単語一覧には残る（明示 `modelContext.save()`）。
      UIテストを `LessonWordRemoveUITests`（スワイプ操作版）に置き換え
      [plan](docs/plans/archive/lesson-words-swipe-remove.md)（2026-07-02）

- [x] Wordsタブの単語一覧の左スワイプ削除を廃止（単語本体の削除は詳細画面の Delete Word に集約）。
      Lesson画面のWords各行の左端に赤い「−」削除ボタンを常時表示し、押すとそのレッスンとの
      リンク（`WordOccurrence`）だけが消えて単語一覧には残る。明示的に `modelContext.save()`。
      UIテスト `LessonWordRemoveButtonUITests` を追加。
      ※一度ユーザー指示で revert したが指示ミスだったため同日中に再実装
      [plan](docs/plans/archive/lesson-words-per-row-remove-button.md)（2026-07-02）

- [x] Words詳細画面の最下部に「Regenerate AI Info」と「Delete Word」ボタンを追加。
      再生成は生成完了時のみ確認ダイアログを挟み、削除は確認後に単語本体を削除
      （cascadeで全レッスンのリンクも消える）して一覧に戻る。明示的に `modelContext.save()`。
      ツールバーの「…」メニュー（Regenerateのみ）はボタンに置き換えて削除。
      Lesson画面Wordsの左スワイプRemoveはユーザー指示で取りやめ（revert）。
      UIテスト `WordDetailButtonsUITests` を追加
      [plan](docs/plans/archive/word-detail-delete-regenerate-buttons.md)（2026-07-02）

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
