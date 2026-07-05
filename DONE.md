# DONE

- [x] 2026-07-05 写真の扱いを検討する（調査・設計）
      写真（`Photo`）を3観点で整理: (1)レッスンのコンテンツとして / (2)レッスンのメモとして /
      (3)レッスンに紐付かない写真の可能性。現状は `Photo.lesson` が非オプショナル＝レッスン必須で、
      「OCR・翻訳される教科書コンテンツ」に一体化しており用途を選べない・メモに写真添付不可・
      未所属写真を表現できないことを確認。データモデルの選択肢（`Photo` に種別フラグ追加 /
      メモ専用エンティティ新設 / `lesson` オプショナル化）をマイグレーション影響とあわせて提示。
      特に `Photo.lesson` オプショナル化は SwiftData ストア互換に加え、`WordOccurrence.sourcePhoto`→
      `lesson`→`ocrText` に依存する `WordRegistrar`/`WordAIInfoGenerator`・カスケード削除への波及に注意。
      具体的なモデル確定・実装は別タスクに切り出す前提。
      plan: docs/plans/archive/photo-handling-review.md

- [x] 2026-07-05 複数ユーザーで使う場合の実装を検討する（調査のみ）
      「複数ユーザー」を4シナリオに分解（A:自分の複数端末 / B:少人数が各自独立 /
      C:データ共有・協働 / D:不特定多数へ配布）。現状は学習データが iOS の SwiftData
      ローカル専用・識別子なし、バックエンドは個人データを持たない共有 AI キャッシュ（認証は
      共有シークレット1個）であることを確認。主戦場は iOS の学習データ層で、A/B は CloudKit
      プライベート DB でバックエンド改修ゼロに解決可能と結論。モデルは `@Attribute(.unique)`
      不使用で相性良好だが、非オプショナル to-one リレーション（`Lesson.schoolClass` 等）の
      optional 化が必要。実装方針は未決4点（目的/Apple専用可否/コスト負担/共有要否）の確定後に判断。
      plan: docs/plans/archive/multi-user-support-review.md

- [x] 2026-07-05 Audio詳細画面で複数レッスンへの追加に対応する
      単語詳細（Appears in Lessons）と同型の仕組みを Audio 詳細にも展開。
      `AudioClip.lesson: Lesson?`（to-one）→ `AudioClip.lessons: [Lesson]`（多対多）に変更し、
      `Lesson.audioClips` の delete rule を cascade → nullify に（レッスン削除でクリップ本体は残す）。
      `AudioDetailView` の単一 Picker を、一覧＋スワイプ解除＋「Add to Lesson」ボタン（`WordLessonPickerView`
      を汎用ピッカーとして再利用）に置換。取り込み経路・`AudioClipRow`（先頭＋"+N"表示）・
      `DebugDataCleaner.deleteClass`（音声ファイルの巻き込み削除を撤去）を多対多に追従。
      plan: docs/plans/archive/audio-multi-lesson.md

- [x] 2026-07-05 Audioの修正：一覧の再生ボタン削除・詳細の自動再生停止
      Audio一覧（Audioタブ・レッスン画面）の各行から再生/停止ボタンを削除し、AudioClipRow を
      タイトル＋レッスン名のみの表示に簡素化。行タップは詳細遷移のみ（自動再生しない）。
      詳細（AudioDetailView）では onAppear で TTSPlaybackService.prepare(url:) を呼び、一時停止状態で
      ロード → TTSPlayerBar を表示してユーザーが再生ボタンを押せるようにした。
      start(player:url:autoPlay:) に autoPlay 引数を追加（false で prepareToPlay のみ）。
      TTSPlaybackServiceTests に testPrepareLoadsWithoutAutoPlaying を追加。
      plan: docs/plans/archive/audio-list-play-button-removal.md

- [x] 2026-07-05 レッスンとの関連付け（単語・音声）を登録後も編集できるようにする
      単語・音声とレッスンの紐付けを、後からユーザーが自由に追加・削除・変更できるように統一。
      Phase 1: 単語詳細（WordDetailView）の「Appears in Lessons」を編集可能化。Add行→WordLessonPickerView
      で追加、行スワイプで削除、行タップで別レッスンへ付け替え（既リンク先は除外して二重リンク防止）。
      WordRegistrar に linkManually / relink / unlink を追加。
      Phase 2: Audio取り込みを「ファイル選択→レッスン選択（既定 None）→取り込み」のフローに変更。
      新規 AudioImportLessonView（sheet）でレッスンを選んでから AudioFileImporter.importFiles(into:) 実行。
      Phase 3: 新規 AudioDetailView。一覧行を NavigationLink 化し、simultaneousGesture で再生と詳細遷移を
      同時実行。詳細で再生/一時停止・タイトル編集・レッスンの追加/変更/解除（Picker, None=解除）・削除。
      下部 TTSPlayerBar は NavigationStack の safeAreaInset に移し、push 後も継続表示。
      AudioClipEditView は詳細画面へ機能移行して廃止（AudioClipRow は LessonsView と共用のため残置）。
      新エンティティ追加なし（WordOccurrence / AudioClip.lesson の既存モデルで実現）。
      plan: docs/plans/archive/lesson-association-words-audio.md

- [x] 2026-07-05 音声タブを追加し、音声を取り込み・レッスン紐付け・再生できるようにする
      Audioタブを新設。iOSの「ファイル」（Dropbox・iCloud・端末内）から音声を取り込み、アプリの
      正式データ（AudioClip）として保存 → 既存 TTSPlayerBar で再生（一時停止・±5秒・シーク・速度）。
      レッスンへの紐付けは任意（単語同様、未紐付けのライブラリ音声も可）。Audioタブのクリップ編集で
      タイトル変更＋レッスン割当、レッスン画面の「Audio」セクションからも取り込み・再生できる。
      データモデル: AudioClip（@Model, title/audioFileName/sourcePath?/byteSize/importedAt/lesson?）＋
      Lesson.audioClips（cascade）。バイナリは AudioStorage（Documents/Audio, UUID.ext, 写真と同作法）。
      新エンティティは全ModelContainer登録＋DebugDataCleaner（全削除・クラス削除でファイルも掃除）対応。
      取り込みは iOS 標準 .fileImporter（allowedContentTypes: [.audio]）＋ AudioFileImporter で、
      セキュリティスコープ付きURLを開閉して読み込む。
      経緯: 当初 Dropbox 直結（SwiftyDropbox の OAuth・案A）で実装したが、App folder スコープだと
      アプリ専用フォルダしか参照できず、普段のフォルダを扱うには Full Dropbox（新アプリ作成が必要）に
      なるため、ユーザー判断で iOSファイルピッカー方式に一本化。SwiftyDropbox 依存・DropboxService・
      DropboxImportView・URLスキーム・DROPBOX_APP_KEY は撤去済み（Dropbox App Console のアプリも削除可）。
      調査/実装プランは docs/plans/archive/ に格納。

- [x] 2026-07-05 writingタブのReviewボタンをもっとボタンに見えるようにする
      Composition 詳細の Review / Re-review ボタンが Form 内で素の青文字だったのを、
      `.buttonStyle(.borderedProminent)` ＋ `.controlSize(.large)` の全幅塗りボタンに変更。
      空状態の「New Composition」ボタンと同じ見た目に揃え、明確にタップ可能に見せた。

- [x] 2026-07-05 作文の反復改善（ラウンド式の履歴スレッド）
      一度添削した後、フィードバックを踏まえて下書きを直し「Re-review」すると次のラウンドとして
      積み上がる反復改善機能。再添削時は過去の全ラウンド（英文・修正・解説）を history として AI に渡し、
      「前回の指摘は直った／まだ残る問題はここ」と改善の推移を踏まえた添削になる。
      iOS: Composition に埋め込み Codable WritingRound（englishText/japaneseText/feedback/createdAt）の
      配列 roundsStorage（nullable ストレージ＋computed rounds、既定 []）を追加。マイグレーション安全のため
      optional 追加、CodingKeys なし。旧データ（単一 feedback）は getter が Round 1 として見せる互換方式で
      破壊的マイグレーション不要（feedback フィールドは残置）。派生 latestFeedback/hasFeedback/
      draftMatchesLastRound を追加。UI（CompositionDetailView）は上部にラウンド履歴を古い順で並べ、下部の
      下書きエディタから次を送る。添削後もエディタの英文は学習者のまま維持（自分で手直しして再送）。
      送信可否は英日非空かつ下書きが最終ラウンドと相違（同一なら無効）。CompositionsView のバッジは
      未添削／編集中／添削済み（×N）。バックエンド: generateWritingFeedback に history 引数を追加し、
      history があれば「複数回書き直して改善中。前回改善点は前向きに触れ残る問題を指摘」旨を前置きして過去
      ラウンドを列挙。/api/writing-feedback で history を任意受理・防御的に正規化（配列でなければ []、直近
      20 件に丸め、各フィールド長クランプ）。DB スキーマ変更なし。実 API 疎通で history 有（前回改善への
      言及＋残る meet→met の指摘）・無（従来単発）の両パスを確認。iOS ビルド・CompositionUITests 成功。
      specs: app-spec.md §3.4、data-model.md §9（WritingRound 追加・旧データ互換方針）。
      plan: docs/plans/archive/writing-iterative-rounds.md
- [x] 2026-07-05 作文機能（英作文の添削込み）
      学習者が英作文を書き、Claude API で添削（修正英文＋日本語解説）を受ける産出練習機能。
      入力は英文＋「伝えたかった意図（日本語）」の2つで、日本語を AI に渡して添削方向を確定させる。
      バックエンド: POST /api/writing-feedback（backend/src/writingFeedback.ts）。structured output で
      correctedText / explanation を返す。config.writingFeedbackModel（既定 claude-sonnet-5）を追加。
      作文本文は毎回異なりキャッシュが効かないためサーバ保存はせず、db の writing_feedback_requests に
      通信ログのみ記録。管理画面（admin.ts）に「作文添削ログ」の一覧・詳細と AI料金の用途逆引きを追加。
      実 API 疎通（過去形・be動詞の誤りを意図どおり修正＋日本語解説）を確認済み。
      iOS: 独立エンティティ Composition（Lesson 非従属）＋埋め込み WritingFeedback を新設し、
      ナビに「Writing」タブを追加。詳細画面で英文・日本語をその場編集 →「Review」で添削取得 → 修正英文
      （単語タップで単語帳登録に接続）＋解説（Markdown）を表示。本文編集後は feedback.generatedAt <
      updatedAt で「古い（要再添削）」を表示。空作文は離脱時に破棄。RemoteWritingFeedbackService で通信。
      SwiftData スキーマ全箇所に Composition.self を登録。DebugDataCleaner の Delete All Data にも
      Composition 削除を追加（UIテスト再実行で未削除バグを検知して修正）。CompositionUITests でタブ遷移・
      両欄入力での Review 活性・一覧表示・空作文破棄を検証（オフライン範囲）。ビルド・テスト成功。
      本プロジェクトは XcodeGen 管理のため pbxproj は project.yml から再生成（Sources 配下は自動取り込み）。
      specs 更新: app-spec.md §3.4 作文・Phase 4、data-model.md §9 Composition / WritingFeedback。
      plan: docs/plans/archive/writing-composition-feedback.md
- [x] 2026-07-04 単語クイズの正解時に気持ちいい音／間違い時にそれとない音を出す
      解答が集約される ReviewSessionView.recordAnswer(isCorrect:) で効果音＋ハプティックを再生。
      音源は同梱方式（ユーザー選択）。tools/generate_quiz_sounds.py で合成（numpy非依存）し、
      Resources/Sounds/correct.caf（C6→E6→G6→C7 の上昇ベルチャイム＝気持ちいい音）と
      wrong.caf（E♭4→B♭3 の低め柔らか下降ブリップ・低音量＝それとない音）を生成。XcodeGen が
      Resources 配下を自動でリソース取り込みするため pbxproj 手編集は不要（xcodegen generate で再生成）。
      再生層は SoundEffectService（AVAudioPlayer 事前ロード、.ambient+mixWithOthers で TTS を止めず
      消音スイッチ尊重、UINotificationFeedbackGenerator の success/warning ハプティック）を新規追加。
      シミュレータ（iPhone 17 Pro）でビルド成功・両cafのバンドル同梱を確認。
      plan: docs/plans/archive/quiz-answer-sounds.md
- [x] 2026-07-04 単語に複数品詞があった場合に単語一覧の訳表示にも表示する
      単語一覧（WordRow）は translation（先頭語義の意味のみ自動補完）を表示していたため、複数品詞を
      持つ単語でも1つの意味しか見えなかった。Word に派生プロパティ listTranslation を追加し、
      aiInfo.senses を走査して先頭語義と異なる品詞の代表意味を「 / 」区切りで連結（例: book → 「本 / 予約する」）。
      先頭は translation を使いユーザー編集を尊重、同一品詞の複数語義は連結しない。WordRow を listTranslation
      表示に差し替え。WordListTranslationTests（複数品詞/同一品詞/3品詞/aiInfo無し/訳語空）を追加、全パス。
      表示形式はユーザー確認済み（「/」区切り）。plan: docs/plans/archive/word-list-multiple-pos.md
- [x] 2026-07-04 英文タップ登録をUIラベル・項目名まで拡張
      「あらゆる英単語の表示を登録可能に」の要望を受け、コンテンツ英文に加えて UI の項目名・
      見出し・静的値・説明文・ナビタイトルも `TappableEnglishText` 化。WordDetailView（全セクション
      見出し・LabeledContent ラベル）、SettingsView（Backend/Native Language/Text-to-Speech/Debug
      見出し・フッター説明文）、LessonsView（Content/Words/Memo/Questions 見出し・空状態文）、
      WordsView（今日の復習カード・空状態）、PhotoDetailView（見出し・状態文）、ReviewSessionView
      （指示文・サマリー・フィードバックラベル）、WordAddView（フッター・Lesson ラベル）を対応。
      各画面ルートに `.wordTapRegistration()` を付与。ナビタイトルは principal ツールバー項目で
      "Photo Detail"/"Review" をタップ可能化（"Add Word" は "Add" ボタンと a11y 衝突するため除外、
      WordDetailView は word.text＝現在語かつUIテスト参照のため据え置き）。
      技術対応: `WordRegistrationModifier` の遷移を `Word` 直接ではなく専用 `WordRoute` 型に変更し、
      既に `Word` 型 navigationDestination を持つ LessonsView との同一スタック型衝突を解消。
      制約（SwiftUI 由来・未対応）: Button/Picker/TextField はコントロール自身がタップを消費するため、
      ラベルの単語タップ化とコントロール操作を両立できず対象外。全55単体テスト＋UI回帰緑。
- [x] 2026-07-04 英文の単語タップで登録をアプリ全体へ展開 [plan](docs/plans/archive/ocr-tap-word-add.md)
      検証（Phase 0, commit 3e903d5）で確認したプレーン英文のタップ登録を、共通の仕組みに
      抽出してアプリ全体の英語へ展開。MarkdownUI 2.4.1 のソース調査で「リンクは標準の
      `AttributedString.link` として描かれ独自 openURL を持たない」ことを確認し、OCR英文も
      見出しハイライト等の書式を保ったまま**トグル無しで常時タップ可能**にできた。
      共通化: `Support/EnglishWordLink.swift`（トークナイザ・マークダウン単語リンク化・
      `eslword://` URL 往復。コード/URL ガード。CJK 混在を除外し英単語のみリンク化）、
      `Support/WordRegistrar.swift`（再利用/新規作成・出現記録の重複ガード付き紐付け・AI生成
      トリガを注入可能に）、`Views/TappableEnglishText.swift`（`WordTapAction` 環境値・
      `TappableEnglishText`/`TappableMarkdown`・`WordRegistrationModifier`＋
      `.wordTapRegistration()`・見出しハイライトを PhotoDetailView から移設）。
      展開先: PhotoDetailView（OCR・`sourcePhoto`/`lesson` 紐付け）、WordDetailView（英英定義・
      語形変化・コロケーション・類義/反意語・用法ノート等の英語欄）、ReviewSessionView
      （フィードバック例文・displayText。回答ボタンは対象外）。WordAddView も WordRegistrar
      利用へ集約（挙動不変）。テスト: `EnglishWordLinkTests`・`WordRegistrarTests` 新規追加、
      全55テスト＋関連UIテスト（LessonWordAdd/WordDetailButtons）緑。
- [x] 2026-07-04 単語問題テキスト入力の自動フォーカスとフォーム改善 [plan](docs/plans/archive/word-quiz-typing-focus-and-form.md)
      復習クイズの `.typing` 形式で、(1) `advance()` で次問が typing の場合に ~0.3s 遅延後
      `isAnswerFieldFocused = true` を立て、出題時にキーボードを自動表示。(2) `typingArea` を刷新：
      "Type your answer" 見出し＋pencil アイコン付き角丸カード（フォーカス中はアクセント枠線）、
      単一行 TextField で Return（.go）送信、Answer ボタンを controlSize(.large) に。
      accessibilityIdentifier は維持。iOS ビルド成功。実機確認は未実施。

- [x] 2026-07-04 単語詳細の Word Forms の左項目名を英語にする [plan](docs/plans/archive/word-forms-english-labels.md)
      backend の wordInfo.ts の inflections[].form を英語の文法用語（past tense, past participle 等）で
      生成するよう structured output の description を変更し dist を再ビルド。既存データは日本語ラベルで
      保存済みのため、iOS の WordDetailView（WordAIInfoSections.englishInflectionLabel）で既知の日本語
      ラベルを英語へマッピングして表示（未知はそのまま）。backend tsc・iOS ビルド成功。

- [x] 2026-07-04 AI単語情報の生成完了後にイラスト生成を自動でバックグラウンド開始する [plan](docs/plans/archive/word-illustration-auto-generate-after-ai-info.md)
      従来はイラスト生成が単語詳細のイラスト行の表示時にしか始まらなかった。共有の
      WordIllustrationGenerator（@MainActor シングルトン、キー単位で多重リクエスト排他）を
      新設し、WordAIInfoGenerator の単語情報生成成功直後に自動でイラスト生成を連結。
      詳細画面を開いていなくても生成が走り、開いていればテキスト表示直後はスピナー →
      完成し次第画像に自動差し替え。WordIllustrationRow は生成状態（@Published）を観測する
      表示専用に変更。ビルド・ユニットテスト全55件成功。実機での確認は未実施。

- [x] 2026-07-04 単語詳細のイラストが生成完了後も「生成中」のまま表示されないバグを修正 [plan](docs/plans/archive/word-illustration-not-refreshing.md)
      調査結果: 画像生成は単語追加時ではなく、単語詳細のイラスト行が表示された瞬間に開始される。
      原因は WordIllustrationRow の body がローカルファイルの存在チェックだけで分岐し
      @State を読んでいなかったため、生成完了しても再描画が起きなかったこと。加えて
      Task {} が MainActor 外で @State を書き込んでいた。表示画像を @State image として
      保持し .task（MainActor）で読み込み/生成する形に修正。iOS 側の60秒タイムアウトが
      バックエンドの生成時間（最大120秒）より短い問題も timeout: 180 指定で解消。
      TTSButton の同パターン（MainActor 外の @State 書き込み）も修正。ビルド・ユニット
      テスト全55件成功。実機での再現確認は未実施。

- [x] 2026-07-04 単語クイズで正解しても Mastery が保存されず 0% のままでクリアできないバグを修正 [plan](docs/plans/archive/review-mastery-persistence-fix.md)
      原因は WordReviewState の CodingKeys リネーム（masteryPercentStorage → "masteryPercent" 等）。
      SwiftData は埋め込み Codable のカラムを実プロパティ名（ZMASTERYPERCENTSTORAGE）で作る一方、
      読み書きは CodingKeys 名で行うためキーが一致せず、値がエラーなく黙って捨てられていた。
      導入時から stepIndex / correctCount / lapseCount も同じ理由で未永続化だった。
      キー名を実プロパティ名に揃えて修正（既存カラム名と一致するためスキーマ変更・マイグレーション
      不要）。ストア経由ラウンドトリップの回帰テスト WordReviewStatePersistenceTests を追加
      （修正前は失敗を確認済み）。ユニットテスト全件成功、旧ストア上での起動確認済み。

- [x] 2026-07-04 単語クイズを習熟度（正解率）方式にする [plan](docs/plans/archive/review-mastery-progress.md)
      1単語1問クリアでは練習量が少ないため、単語ごとに masteryPercent（0〜100%、日をまたいで
      永続）を導入。正解+25%/不正解−25%で、100%到達時のみクリアとして Leitner 間隔
      （3→7→14→30→90日）で dueDate を前進させ習熟度を0に戻す。不正解は step 0 リセットのみで
      dueDate は変えず、クリアまで毎日出題対象に残る。セッションは5語・最大10問、未クリア単語の
      ラウンドロビンで同一単語の連続出題を回避し、全単語クリアで早期終了。reviewState は毎解答
      反映（retryQueue 廃止）。出題が動的になったため音声は対象5語の全問題分を開始前に一括DL。
      SwiftData 埋め込み Codable のため masteryPercent は nullable ストレージ + computed 既定値
      0 のパターンで追加。ユニットテスト53件成功。

- [x] 2026-07-04 vtt1（例文リスニング穴埋め入力）を復活させる [plan](docs/plans/archive/restore-vtt1.md)
      vtt1 は音声が完全文（単語の発音込み）を読み上げるため答えを一意に特定でき、
      tt2 の廃止理由（空所の候補が多すぎる）は当てはまらないと判明したため復活。
      backend の AI_FORMAT_SPECS・iOS の ReviewQuestionFormat に再追加し、起動時
      クリーンアップは tt2 のみに変更。あわせて vtt1 の生成指示が「vtc1 の入力版」と
      別グループの形式を参照していて生成漏れする問題（banana で再現）を自己完結の
      指示文に修正。保存済み5単語を再生成し、全単語に vtt1 が3問ずつ保存され
      音声プリ合成も成功したことを確認済み。

- [x] 2026-07-04 単語問題で穴埋めをテキスト入力するのは無くす（tt2・vtt1 の廃止） [plan](docs/plans/archive/remove-fill-blank-typing.md)
      空所の候補が多すぎて答えを特定できないため、例文穴埋め入力（tt2）と
      例文リスニング穴埋め入力（vtt1）を廃止。backend は AI_FORMAT_SPECS から削除して
      生成を停止し、起動時に保存済み行を DELETE（冪等）。iOS は ReviewQuestionFormat から
      両ケースを削除（旧データは要素単位デコードで自然に除外）。4択版の tc3・vtc1 や
      tt1・tt3・vt1・vt2 など答えが一意な入力形式は存続。ローカルサーバ再起動で
      既存24行の削除、banana の再生成で両形式が生成されないことを確認済み。

- [x] 2026-07-04 単語クイズの最初に音声データをダウンロードしてから始める。DLは進捗がわかるようにバーを表示 [plan](docs/plans/archive/quiz-audio-predownload.md)
      セッション開始時に main キュー分の出題を ReviewSessionPlanner で事前確定し
      （FormatSelector の逐次比率調整と同一挙動・テストで検証）、必要な音声だけを
      QuizAudioDownloader（並列2・1回リトライ）で一括DLしてから出題を開始するようにした。
      DL中は「Preparing audio… n/m」の進捗バーを表示し、Close でキャンセル可能。
      失敗テキストを含む問題は同じ単語の別形式（音声形式はローカル保存済みに限定）へ
      差し替えて続行、retry の出題もローカル音声がある問題に限定。端末内蔵TTSは
      最終安全網として存続。ユニットテスト8件追加・全パス、ローカルサーバでの
      E2E（testTodayReviewFlowWithServerQuestions）とサーバ不達テストもパス確認済み。

- [x] 2026-07-03 管理画面で単語クイズの音声データを再生できるようにする [plan](docs/plans/archive/admin-quiz-audio-playback.md)
      単語クイズ詳細（/admin/quiz-questions/item）の問題テーブルに「音声」列を追加し、
      audioText のプリ合成済み音声（sha256("flash|text") で tts_audio を照合）を
      TTS一覧と同じ <audio> プレイヤーで再生できるようにした。未合成は「音声未合成」、
      audioText なしは「—」表示。配信は既存 /admin/tts/:id/audio を再利用（新規APIなし）。
      ローカルサーバで apple / banana のページに全プレイヤーが出力され audio/wav が
      返ることを確認済み。
- [x] 2026-07-03 単語追加時に入力欄に最初からフォーカスを当てる（クラス作成、レッスン作成も同様に） [plan](docs/plans/archive/word-add-focus.md)
      WordAddView に @FocusState + .onAppear によるフォーカス処理を追加し、単語追加シートを
      開いた直後から入力できるようにした。ClassAddView / LessonAddView は既に同パターンで
      実装済みだったため確認のみ。LessonWordAddUITests にシート表示直後のキーボードフォーカスを
      検証するアサーション（hasKeyboardFocus のポーリング待ち）を追加し、パスを確認済み。
- [x] 2026-07-03 単語問題の音声生成をAIで行う [plan](docs/plans/archive/quiz-audio-ai-generation.md)
      クイズ問題の生成成功直後（/api/quiz-questions/generate と管理画面 regenerate の2経路）に、
      サーバ側で全 audioText を fire-and-forget で一括プリ合成するようにした（並列2・モデルは flash 固定）。
      /api/tts のキャッシュ検索→合成→保存処理は新規 ttsStore.ts の getOrSynthesizeTtsAudio に関数化
      （/api/tts の挙動は不変）。iOS はクイズ音声を AppSettingsKeys.quizTTSModel = "flash" 固定で参照し、
      ReviewSessionView の ttsModel 設定依存を削除（端末内蔵TTSフォールバックは存続）。
      banana（API経路・20件）/ apple（管理画面経路・19件）で全件合成成功・キャッシュヒット時の
      Gemini 非呼び出し・iOS 側キー（sha256("flash|text")）一致を確認済み。
- [x] 2026-07-03 TTSはキャラクター2人をランダムで選択して生成する。アプリのSettingのキャラ選択は削除 [plan](docs/plans/archive/tts-random-voice.md)
      音声キャラの決定をサーバに一元化。/api/tts が生成時に chobi/naruko からランダム選択し、
      キャッシュキーを sha256("model|text") に変更（同一テキストは初回に選ばれたキャラで固定＝キャッシュ有効）。
      iOS からは voice の概念を削除（Settings の Voice ピッカー、AppSettingsKeys.ttsVoice、
      GeminiSpeechService / TTSAudioStore / 各 View の voice 引数）。旧形式キーのキャッシュは
      ヒットしなくなり必要に応じて再生成される（移行処理なし）。TTSAudioStoreTests 更新・全パス確認済み。
- [x] 2026-07-03 単語詳細のイラストをバックグラウンドで生成して終わったら表示する [plan](docs/plans/archive/word-illustration-auto-generate.md)
      手動の「Generate Illustration」ボタンを廃止し、詳細画面を開いたら自動でバックグラウンド生成を
      開始（スピナー表示）→ 完了で画像表示に切り替わるようにした。失敗時はエラー + Retry ボタン。
      イラストセクションは AI 情報 completed 時のみ描画されるため素材未生成の状態で走ることはない。
      ローカル backend + シミュレータの UI テストで自動生成→表示を確認済み。
- [x] 2026-07-03 管理画面の単語一覧にクイズ問題の生成ボタンを追加 [plan](docs/plans/archive/admin-words-quiz-generate-button.md)
      実機の Today's Review が「Preparing Questions」のまま進まない問題（本番の quiz_questions が空、
      アプリの fire-and-forget 自己修復も不発）への対処。/admin/words 一覧と単語詳細に「クイズ」列を追加し、
      0件は生成ボタン（既存の /admin/quiz-questions/regenerate を利用、失敗時はエラーがブラウザに表示され
      診断に使える）、1件以上は問題数を詳細リンクで表示。ローカルで experience 61問の実生成を確認済み。
- [x] 2026-07-03 WordReviewState 追加フィールドによるマイグレーション失敗を修正（実機で「クラスを作成しても表示されない」バグ） [plan](docs/plans/archive/fix-reviewstate-migration-failure.md)
      原因: 復習クイズ Phase 2 で埋め込み Codable の WordReviewState に非オプショナルの
      stepIndex/correctCount/lapseCount を追加したため、既存 Word 行を持つストア（実機）で
      ライトウェイトマイグレーションが失敗しストア自体が開けなくなっていた。
      修正: ストレージをオプショナル（nullable カラム）にして公開 API は computed で 0 既定値に。
      あわせて ModelContainer 生成失敗時のエラー画面（StoreLoadErrorView）と
      save() 失敗をログする ModelContext.saveOrLog() を追加（try? save 11箇所を置換）。
      実機ストアのコピーで旧スキーマ→新スキーマのマイグレーション成功・データ維持を検証済み。
- [x] 2026-07-03 単語を覚える問題機能を設計・実装する [plan](docs/plans/archive/word-memorization-quiz.md)
      間隔反復の復習クイズ機能一式。調査2件（拡張間隔の科学的根拠 / 音声入力の実現方法）、
      Phase 1: スペック確定（固定ステップ Leitner 方式・28出題形式・Question の位置づけ注記）、
      Phase 2: ReviewScheduler・FormatSelector（出題/回答モダリティの比率調整）・
      WordReviewState 拡張（stepIndex/correctCount/lapseCount）+ ユニットテスト、
      Phase 3: ReviewSessionView（出題→回答→フィードバック→サマリー、上限20問・
      不正解は末尾再出題）・Words タブ「今日の復習」カード・タブバッジ、
      Phase 4: WordDetailView に Review セクション（次回復習日 Due today 表示・
      ステップ・回数・正答率・最終復習日）。
      ※問題の生成・保存は途中でサーバ AI 生成方式
      （[plan](docs/plans/archive/quiz-questions-server-storage.md)）へ移行。
      音声入力形式（TV/IV/VV 系）は将来の拡張候補としてプラン §7 に整理済み。
- [x] 2026-07-03 復習クイズの問題をサーバで AI 生成・保存し、複数バリエーションからランダム出題する
      [plan](docs/plans/archive/quiz-questions-server-storage.md)
      backend: quiz_questions テーブル + quizQuestions.ts（24形式を形式グループ並列の
      callStructured で生成・構造検証、イラスト系4形式はルール生成）、
      POST /api/quiz-questions/generate・/query、管理画面 /admin/quiz-questions
      （一覧・詳細・再生成・削除）。生成コスト実測 約$0.036/単語（haiku・1形式3バリエーション）。
      iOS: ReviewQuestion を Codable 化しサーバ問題のみで出題（形式は FormatSelector の
      比率調整、同形式のバリエーションからランダム選択）。単語情報の生成成功後に自動生成
      トリガ + セッション開始時の自己修復トリガ。ローカル生成（ReviewQuestionBuilder・
      GrammarLabelMapping）は削除。オフライン時はリトライ画面、未生成は Preparing 表示。
      ユニットテスト47件 + オフラインUIテスト + ローカルサーバE2E（TEST_RUNNER_REVIEW_E2E_*）で確認。
- [x] 2026-07-03 アイコンとアプリ名の変更 [plan](docs/plans/archive/change-app-icon-and-name.md)
      表示名を「ESL Assistant」に変更（project.yml に CFBundleDisplayName 追加、
      ターゲット名・スキーム名・Bundle ID は不変で run-ios-device.sh 無修正）。
      支給画像を 1024x1024 にリサイズして AppIcon.appiconset に配置、
      ASSETCATALOG_COMPILER_APPICON_NAME の typo 修正。
      管理画面ページタイトル・起動ログ・README も「ESL Assistant」に統一。
      xcodebuild / tsc で検証済み。
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
