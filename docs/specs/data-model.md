# データモデル仕様（v1）

[app-spec.md](app-spec.md) 9章「データモデルの詳細スキーマ」に対応する詳細仕様。
策定経緯: [docs/plans/archive/data-model-design.md](../plans/archive/data-model-design.md)

## 0. 前提

- 永続化フレームワークは **SwiftData**（`ios/project.yml` の deploymentTarget が iOS 17 のため採用可能）を前提とする
- 仕様書 4章のとおり、ユーザーデータはすべて端末内ローカル保存（クラウド同期なし）
- 画像本体（撮影写真）はファイルシステム（`Documents/Photos/` 等）に保存し、
  SwiftData モデルにはファイル名のみを持たせる（DB に Data blob を持たせない）
- 各エンティティは `id: UUID` を主キーとする
- 「レッスンごとのビュー」「全体の一覧ビュー」（仕様書4章）は、`Lesson`（および `Class`）との関連を
  辿るクエリ／それらを介さない全件クエリの両方を SwiftData の `@Query` でサポートできる形にする
- `Word` と `Composition` は `Lesson` に従属しない独立エンティティとする（1章参照）。同じ単語が
  複数レッスンの教科書に出てきても 1つの `Word` レコードに統合され、復習状態（`reviewState`）も
  共有される。`Composition`（作文）は自主学習として自由に書き溜める
- 本資料は **スキーマ**を確定するもの。以下は仕様書9章に残課題として残り、本資料のスコープ外
  - 対応言語（母語）の具体的なリスト
- 単語帳の間隔反復アルゴリズムは固定ステップの Leitner 方式で確定した（§5 参照。
  策定経緯: [docs/plans/archive/word-memorization-quiz.md](../plans/archive/word-memorization-quiz.md)）

## 1. エンティティ関連図（概要）

```
Class 1 ── * Lesson
Lesson 1 ── * Photo
Lesson 1 ── * Question ── * (sourcePhoto: Photo?)
Question 1 ── * QuizResult
Lesson * ── * AudioClip   (多対多・nullify。レッスン非依存のライブラリ音声も許容)
Lesson * ── * Document    (多対多・nullify。レッスン非依存のライブラリ文書も許容)

Lesson * ── * Word   (中間エンティティ WordOccurrence 経由)
WordOccurrence ── 1 Lesson
WordOccurrence ── 1 Word
WordOccurrence ── * (sourcePhoto: Photo?)
WordOccurrence ── * (sourceAudio: AudioClip?)
WordOccurrence ── * (sourceDocument: Document?)
```

- `Lesson` は `Class` に必須で属する（仕様書4章: クラス／レッスンの2段階管理単位）
- `Photo` / `Question` は `Lesson` に必須で属する（仕様書4章: レッスン単位の管理）
- `AudioClip` は `Lesson` に**従属しない**。0個以上のレッスンへ紐付けられ（多対多・削除時は nullify）、
  どのレッスンにも属さないライブラリ音声としても存続する（[§4.5](#45-audioclip取り込み音声とその文字起こし翻訳)）
- `Document`（PDF/DOCX）も `AudioClip` と同型で `Lesson` に**従属しない**。0個以上のレッスンへ紐付けられ
  （多対多・削除時は nullify）、どのレッスンにも属さないライブラリ文書としても存続する（[§4.6](#46-document取り込み文書pdfdocxとその抽出翻訳)）
- `Word` は `Lesson` に従属しない独立エンティティ。`Lesson` との関連は `WordOccurrence`
  （「どのレッスンでこの単語に出会ったか」の出現記録）を介した多対多とする
- `Question.sourcePhoto` / `WordOccurrence.sourcePhoto` / `WordOccurrence.sourceAudio` /
  `WordOccurrence.sourceDocument` は任意の参照（手動登録や、複数写真にまたがる場合等を許容するため）。
  `sourcePhoto` は写真OCR由来、`sourceAudio` は音声文字起こし由来、`sourceDocument` は文書抽出由来の
  タップ登録元を表す

### データ構造ツリー

`Class` 配下の所有階層と、`Lesson` に従属しない `Word` / `Composition` を別ツリーとして示す。

```
Class
├─ id / name / createdAt
└─ lessons: [Lesson]                         (1 Class - * Lesson)
    ├─ id / title / createdAt
    ├─ photos: [Photo]                       (1 Lesson - * Photo)
    │   ├─ id
    │   ├─ imageFileName
    │   ├─ capturedAt
    │   ├─ processingStatus: PhotoProcessingStatus
    │   ├─ ocrText?
    │   ├─ translatedText?
    │   └─ translationLanguage?
    ├─ wordOccurrences: [WordOccurrence]      (1 Lesson - * WordOccurrence)
    │   ├─ id
    │   ├─ word: Word                         (参照、所有はしない)
    │   ├─ sourcePhoto?: Photo                (任意の参照、所有はしない)
    │   ├─ sourceAudio?: AudioClip            (任意の参照、所有はしない)
    │   ├─ sourceDocument?: Document          (任意の参照、所有はしない)
    │   └─ occurredAt
    ├─ audioClips: [AudioClip]                (* Lesson - * AudioClip、nullify、所有はしない。詳細は §4.5)
    ├─ documents: [Document]                  (* Lesson - * Document、nullify、所有はしない。詳細は §4.6)
    └─ questions: [Question]                 (1 Lesson - * Question)
        ├─ id
        ├─ sourcePhoto?: Photo               (任意の参照、所有はしない)
        ├─ type: QuestionType
        ├─ prompt / choices / correctAnswer
        ├─ explanation?
        ├─ generatedAt
        └─ results: [QuizResult]             (1 Question - * QuizResult)
            ├─ id
            ├─ userAnswer
            ├─ isCorrect
            └─ answeredAt

Word                                          (Lessonに従属しない独立エンティティ)
├─ id
├─ text / translation
├─ exampleSentence?
├─ exampleSentenceSource?: ExampleSentenceSource
├─ partOfSpeech? / grammarNote?
├─ registeredAt
├─ reviewState: WordReviewState               (埋め込み、全レッスン共有)
│   ├─ dueDate
│   ├─ lastReviewedAt?
│   ├─ reviewCount
│   ├─ stepIndex
│   ├─ correctCount
│   └─ lapseCount
└─ occurrences: [WordOccurrence]              (1 Word - * WordOccurrence)

Composition                                   (Lessonに従属しない独立エンティティ)
├─ id
├─ englishText / japaneseText
├─ createdAt / updatedAt
├─ explanationLanguage
└─ rounds: [WritingRound]                     (改善の履歴。古い順。未添削なら空)
    ├─ id / englishText / japaneseText / createdAt
    └─ feedback: WritingFeedback              (埋め込み)
        ├─ correctedText
        ├─ explanation
        ├─ model
        └─ generatedAt
```

- 実線の `├─ lessons / photos / wordOccurrences / questions / results / occurrences` は
  **所有関係**（親削除でカスケード削除）
- `WordOccurrence.word` / `sourcePhoto?` は所有しない**参照のみ**の関連
- `Lesson` 削除時は配下の `WordOccurrence` のみカスケード削除する。`Word` 本体は他のレッスンからも
  参照されている可能性があるため削除しない（ユーザーが単語帳から明示的に削除した場合のみ `Word` と
  その `occurrences` を削除する）

## 2. Class（クラス）

レッスンをまとめる親単位。受講しているコース・科目に相当する（仕様書4章）。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| name | String | クラス名（ユーザー入力、例:「ESL Beginner A」） |
| createdAt | Date | 作成日時 |
| lessons | [Lesson] | 関連レッスン（to-many, cascade delete） |

- クラス削除時は配下の `Lesson` とその下の `Photo` / `WordOccurrence` / `Question` / `QuizResult` を
  カスケード削除する（`Word` 本体は他クラスのレッスンからも参照され得るため削除しない）

## 3. Lesson（授業）

クラス内の1回分の授業の単位。ユーザーが手動で作成・切り替えを行う（仕様書4章）。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| class | Class | 所属クラス（to-one, 必須） |
| title | String | レッスン名（ユーザー入力、例:「Unit 3 Reading」） |
| createdAt | Date | 作成日時 |
| photos | [Photo] | 関連写真（to-many, cascade delete） |
| wordOccurrences | [WordOccurrence] | この授業で出会った単語の出現記録（to-many, cascade delete） |
| questions | [Question] | 関連問題（to-many, cascade delete） |
| audioClips | [AudioClip] | 紐付けた取り込み音声（to-many, **nullify**）。レッスン削除でクリップ本体は残す（[§4.5](#45-audioclip取り込み音声とその文字起こし翻訳)） |
| documents | [Document] | 紐付けた取り込み文書（PDF/DOCX）（to-many, **nullify**）。レッスン削除で文書本体は残す（[§4.6](#46-document取り込み文書pdfdocxとその抽出翻訳)） |

- 自動の日付区切りは行わない。`createdAt` は記録のみで区切り条件には使わない
- レッスン削除時は配下の `Photo` / `WordOccurrence` / `Question` / `QuizResult` をカスケード削除する
  （`WordOccurrence` が指す `Word` 本体は削除しない）
- レッスンの単語帳ビュー（仕様書4章）は `wordOccurrences.map { $0.word }` で取得する

## 4. Photo（撮影画像）

教科書ページ等の撮影画像と、その OCR・翻訳結果（仕様書3.1章）。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| lesson | Lesson | 所属レッスン（to-one, 必須） |
| imageFileName | String | `Documents/Photos/` 配下のファイル名（画像本体はDB外） |
| capturedAt | Date | 撮影日時 |
| processingStatus | PhotoProcessingStatus | OCR・翻訳の処理状態（下記 enum） |
| ocrText | String? | 文字起こし結果（未処理時は nil） |
| translatedText | String? | 翻訳結果（未処理時は nil） |
| translationLanguage | String? | 翻訳先言語コード（処理時点のユーザー設定母語を記録） |

### PhotoProcessingStatus（enum）

| 値 | 説明 |
|---|---|
| pending | 撮影済み・未送信（オフライン等） |
| processing | Claude API 呼び出し中 |
| completed | OCR・翻訳完了 |
| failed | 失敗（再試行可能） |

- 撮影自体はオフラインでも可能なため `pending` を初期状態として持つ（仕様書3.1章・5.1章）

## 4.5 AudioClip（取り込み音声とその文字起こし・翻訳）

iOSの「ファイル」（Dropbox・iCloud・端末内）から取り込んだ音声クリップと、その英文文字起こし・
日本語翻訳結果。`Photo` の音声版で、写真OCRと同じ4層構成（状態＋結果を持つモデル → Remote サービス →
状態遷移 → 詳細Viewで分岐表示）を踏襲する。音声本体（バイナリ）は `Documents/Audio/` にファイル保存し、
モデルはメタデータのみ持つ（DBに Data blob を持たせない）。
策定経緯: [docs/plans/audio-transcription-translation.md](../plans/audio-transcription-translation.md)。

- **レッスンに従属しない**独立エンティティ。0個以上のレッスンへ紐付けられ（多対多）、どのレッスンにも
  属さないライブラリ音声としても存続する。レッスン削除時は紐付けが nullify されるだけでクリップは残る
- 文字起こし・翻訳は取り込み時の自動処理ではなく、**詳細画面の手動ボタン**で1クリップずつ実行する
  （音声は長くコストも高いため）。v1 は短いクリップ（Gemini インライン上限 ≈14MB）のみ対象

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| title | String | 表示名（既定は取り込みファイル名から拡張子を除いたもの。編集可） |
| audioFileName | String | `Documents/Audio/` 配下の実ファイル名（`UUID.ext`） |
| sourcePath | String? | 取り込み元の参照用パス（予備。ファイル取り込みでは nil） |
| byteSize | Int | 音声ファイルのバイト数 |
| importedAt | Date | 取り込み日時 |
| lessons | [Lesson] | 紐付くレッスン（0個以上、多対多、nullify） |
| processingStatus | AudioProcessingStatus | 文字起こし・翻訳の処理状態（下記 enum。既定 `pending`） |
| processingErrorMessage | String? | 失敗時のユーザー向けメッセージ（未対応形式・サイズ超過・401案内等） |
| transcriptText | String? | Gemini による英文逐語文字起こし（Markdown。未処理時は nil） |
| translatedText | String? | transcript の全訳（Markdown。既存 `translateText` で生成。未処理時は nil） |
| translationLanguage | String? | 訳の言語コード（処理時点のユーザー設定母語を記録） |

### AudioProcessingStatus（enum）

`PhotoProcessingStatus` と同型（`String, Codable`）。

| 値 | 説明 |
|---|---|
| pending | 取り込み済み・未処理（初期状態） |
| processing | 文字起こし＋翻訳API呼び出し中 |
| completed | 文字起こし・翻訳完了 |
| failed | 失敗（再試行可能） |

- 文字起こしは **Gemini**（音声入力対応）で英文へ、翻訳は既存 `translateText`（Claude）で英→日を行う
  2段構成。バックエンド `POST /api/transcribe-translate` が両者を実行して返す
- 完了時、詳細画面は transcript 英文を単語タップ登録可能（`TappableMarkdown`）に表示する。
  タップ登録は出現記録に `sourceAudio` として当該クリップを記録し（[§6](#6-wordoccurrence出現記録)）、
  写真OCRの `sourcePhoto` と同様に AI 単語情報生成へ transcript を文脈として渡す
- 追加フィールドはすべて optional か default 付きで、既存ストアの軽量マイグレーションを維持する
  （`processingStatus` は default 付き non-optional、結果系は optional）

## 4.6 Document（取り込み文書PDF/DOCXとその抽出・翻訳）

iOSの「ファイル」（iCloud・端末内等）から取り込んだ文書（PDF / Word `.docx`）と、その英文抽出・
日本語翻訳結果。`AudioClip` の文書版で、写真OCR・音声と同じ4層構成（状態＋結果を持つモデル →
Remote サービス → 状態遷移 → 詳細Viewで分岐表示）を踏襲する。文書本体（原本バイナリ）は
`Documents/Documents/` にファイル保存し、モデルはメタデータのみ持つ（DBに Data blob を持たせない）。
策定経緯: [docs/plans/document-import.md](../plans/document-import.md)。

- **レッスンに従属しない**独立エンティティ。0個以上のレッスンへ紐付けられ（多対多）、どのレッスンにも
  属さないライブラリ文書としても存続する。レッスン削除時は紐付けが nullify されるだけで文書は残る
- 抽出・翻訳は取り込み時の自動処理ではなく、**詳細画面の手動ボタン**で1文書ずつ実行する（v1）。
  抽出＋翻訳は独立サービスに切り出し、将来は取り込み時自動へ呼び出し箇所を差し替えるだけで切替可能にする
- 抽出はハイブリッド: 埋め込みテキスト層があればそれを抽出、無い（スキャンPDF等）場合は画像OCRに
  フォールバックする（すべてサーバ側で実行。詳細は Phase 2）

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| title | String | 表示名（既定は取り込みファイル名から拡張子を除いたもの。編集可） |
| documentFileName | String | `Documents/Documents/` 配下の実ファイル名（`UUID.ext`） |
| fileKind | DocumentKind | 文書種別（下記 enum）。ビューア出し分け・抽出経路の判定に使う |
| sourcePath | String? | 取り込み元の参照用パス（予備。ファイル取り込みでは nil） |
| byteSize | Int | 文書ファイルのバイト数 |
| importedAt | Date | 取り込み日時 |
| lessons | [Lesson] | 紐付くレッスン（0個以上、多対多、nullify） |
| processingStatus | DocumentProcessingStatus | 抽出・翻訳の処理状態（下記 enum。既定 `pending`） |
| processingErrorMessage | String? | 失敗時のユーザー向けメッセージ（未対応形式・サイズ超過・401案内等） |
| extractedText | String? | 抽出/OCR された英文（Markdown。未処理時は nil）。`AudioClip.transcriptText` に相当 |
| translatedText | String? | extractedText の全訳（Markdown。既存 `translateText` で生成。未処理時は nil） |
| translationLanguage | String? | 訳の言語コード（処理時点のユーザー設定母語を記録） |

### DocumentKind（enum）

ビューアの出し分けと抽出経路の判定に使う。`String, Codable`。

| 値 | 説明 |
|---|---|
| pdf | PDF（`.pdf`）。ビューアは `PDFView` |
| docx | Word（`.docx`）。ビューアは `QuickLook` |

- `Document` はモデル追加と同一コミットで入るため、`fileKind` は非オプショナル enum を直付けしてよい
  （既存行が無く materialize でクラッシュしない）。取り込み時に確定するため既定値は持たない

### DocumentProcessingStatus（enum）

`PhotoProcessingStatus`・`AudioProcessingStatus` と同型（`String, Codable`）。

| 値 | 説明 |
|---|---|
| pending | 取り込み済み・未処理（初期状態） |
| processing | 抽出＋翻訳API呼び出し中 |
| completed | 抽出・翻訳完了 |
| failed | 失敗（再試行可能） |

- 完了時、詳細画面は抽出英文を単語タップ登録可能に表示する。タップ登録は出現記録に `sourceDocument`
  として当該文書を記録し（[§6](#6-wordoccurrence出現記録)）、写真OCRの `sourcePhoto`・音声の `sourceAudio`
  と同様に AI 単語情報生成へ抽出テキストを文脈として渡す
- `processingStatus` は `AudioClip` と同じ **storage + computed 方式**（実ストレージは optional で
  NULL 許容、公開 API は computed で NULL を `.pending` として返す）で持ち、将来の軽量マイグレーションを
  壊さない。結果系フィールドはすべて optional 追加のみ
- 原本（PDF/DOCX）は抽出前（pending/failed）でもアプリ内で閲覧できる（表示は抽出結果に依存しない。
  PDF=`PDFView` / DOCX=`QuickLook`。Phase 4.5）

## 5. Word（単語帳）

`Lesson` に従属しない独立エンティティ。同じ単語は複数レッスンの教科書に出てきても
1つの `Word` レコードに統合し、復習状態（`reviewState`）を共有する。
レッスンとの関連は [WordOccurrence](#6-wordoccurrence出現記録) を参照。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| text | String | 見出し語・フレーズ |
| translation | String | 訳語 |
| exampleSentence | String? | 例文 |
| exampleSentenceSource | ExampleSentenceSource? | 例文の出典（下記 enum） |
| partOfSpeech | String? | 品詞 |
| grammarNote | String? | 文法情報 |
| registeredAt | Date | 初回登録日時 |
| reviewState | WordReviewState | 復習用の状態（下記、埋め込み、全レッスン共有） |
| occurrences | [WordOccurrence] | この単語が登場したレッスンの出現記録（to-many, cascade delete） |

### ExampleSentenceSource（enum）

| 値 | 説明 |
|---|---|
| textbook | 教科書からの抜粋 |
| aiGenerated | AI 生成 |

### WordReviewState（埋め込み構造体）

復習クイズ／間隔反復（仕様書3.2章）に使う状態。アルゴリズムは**固定ステップの Leitner 方式**で
確定した（策定経緯: [docs/plans/archive/word-memorization-quiz.md](../plans/archive/word-memorization-quiz.md) §3.1）。
レッスンをまたいでも同じ単語であればこの状態を共有する（レッスンごとに復習履歴が分散しない）。

- 復習ステップ: `[3日, 7日, 14日, 30日, 90日]`（stepIndex 0〜4）。90日到達後は 90日間隔を維持
- 習熟度方式（[docs/plans/archive/review-mastery-progress.md](../plans/archive/review-mastery-progress.md)）:
  解答のたびに `masteryPercent` を増減する（正解 +25% / 不正解 −25%、0〜100 でクランプ）
  - 100% 到達 = クリア → `dueDate = 今日 + 現在ステップの日数` とし、ステップを1つ進め
    （最終ステップでは維持）、masteryPercent を 0 に戻す（新規単語の初回クリアは +3日）
  - 不正解 → stepIndex 0 に戻す。dueDate は変えない（クリアするまで出題対象に残る）
- 判定はローカル日付（Calendar）基準。`dueDate <= 今日` の単語が「今日の復習」対象
- 計算ロジックはモデルから分離した純関数 `ReviewScheduler` に置く（SM-2 / FSRS への将来差し替えを想定）

| フィールド | 型 | 説明 |
|---|---|---|
| dueDate | Date | 次回復習予定日（初期値: 登録日） |
| lastReviewedAt | Date? | 直近の復習日時 |
| reviewCount | Int | 復習回数（初期値 0） |
| stepIndex | Int | 現在の復習ステップ（初期値 0） |
| correctCount | Int | 累計正解数（初期値 0） |
| lapseCount | Int | 不正解でリセットされた回数（初期値 0） |
| masteryPercent | Int | 現在周回の習熟度 0〜100%（初期値 0。100 でクリアと同時に 0 へ戻る） |

- 既存レコードには追加フィールドをデフォルト値（0）で吸収する（SwiftData 埋め込み構造体のため
  マイグレーション不要）

## 6. WordOccurrence（出現記録）

`Word` と `Lesson` の多対多関連を表す中間エンティティ。「どのレッスンの教科書で
この単語に出会い、どの写真のOCR結果／音声の文字起こしからタップ登録したか」を1件ずつ記録する。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| word | Word | 対象単語（to-one, 必須。所有はしない参照） |
| lesson | Lesson | 出会ったレッスン（to-one, 必須） |
| sourcePhoto | Photo? | 写真OCR結果のタップ登録の場合の参照元（手動・音声・文書由来では nil） |
| sourceAudio | AudioClip? | 音声文字起こしのタップ登録の場合の参照元（手動・写真・文書由来では nil）。`sourcePhoto` の音声版 |
| sourceDocument | Document? | 文書抽出結果のタップ登録の場合の参照元（手動・写真・音声由来では nil）。`sourcePhoto` の文書版 |
| occurredAt | Date | このレッスンでの登録・紐づけ日時 |

- `sourcePhoto` / `sourceAudio` / `sourceDocument` はいずれも任意の参照で、AI 単語情報生成に
  本文（OCR結果／transcript／抽出テキスト）を文脈として渡すために保持する。手動登録では全て nil（文脈なし生成）
- 同一 `Word` が同一 `Lesson` で複数回タップ登録された場合も、出現履歴として複数件許容する。
  重複ガードは `lesson + sourcePhoto + sourceAudio + sourceDocument` の一致で判定する
- `Lesson` 削除時にカスケード削除される（`Word` 側からの削除ではない限り `Word` 自体は残る）
- `Word` 削除時（ユーザーが単語帳から明示的に削除した場合）もカスケード削除される
- `sourcePhoto` / `sourceAudio` / `sourceDocument` は逆リレーションを張らない任意参照のため、
  写真・音声クリップ・文書削除時は `ModelContext.deletePhoto(_:)` / `deleteAudioClip(_:)` /
  `deleteDocument(_:)` が参照を nil 化する（出現自体は残す）

## 7. Question（問題）

教科書内容から AI が自動生成する練習問題（仕様書3.3章）。

> **位置づけ**: `Question` / `QuizResult` は **AI 生成問題（v2、仕様書3.3章、レッスン紐づけ）用**のモデル。
> 単語帳の復習クイズ（仕様書3.2章）はレッスンに紐づかず、問題は backend が AI 生成して
> サーバ（`quiz_questions` テーブル）に保存したものを取得して出題するため、端末側では
> `Question` レコードを作成せず、結果は `Word.reviewState` の更新のみで記録する
> （設計: [docs/plans/quiz-questions-server-storage.md](../plans/archive/quiz-questions-server-storage.md)）。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| lesson | Lesson | 所属レッスン（to-one, 必須） |
| sourcePhoto | Photo? | 出題元の写真（複数写真にまたがる場合等は nil 許容） |
| type | QuestionType | 出題形式（下記 enum） |
| prompt | String | 設問文 |
| choices | [String] | 選択肢（`multipleChoice` 以外では空配列） |
| correctAnswer | String | 正答（形式により選択肢文字列／穴埋め語句／並べ替え後の文等） |
| explanation | String? | 解説（AI生成） |
| generatedAt | Date | 生成日時 |
| results | [QuizResult] | 演習結果の履歴（to-many, cascade delete） |

### QuestionType（enum）

| 値 | 説明 |
|---|---|
| multipleChoice | 選択肢（多肢選択）問題 |
| fillInBlank | 穴埋め問題 |
| rearrange | 記述・並べ替え問題 |

- 難易度調整 UI は持たない（仕様書3.3章）ため難易度フィールドは設けない

## 8. QuizResult（演習結果）

1問への解答1回分の記録。正答率・履歴の算出はこのエンティティの集計で行う（仕様書3.3章）。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| question | Question | 対象問題（to-one, 必須） |
| userAnswer | String | ユーザーの解答 |
| isCorrect | Bool | 正誤 |
| answeredAt | Date | 解答日時 |

- 同一 `Question` に対して複数回の `QuizResult` を許容する（再挑戦・履歴表示のため）
- レッスン単位／全体の正答率は `Lesson.questions.results`（または全件の `QuizResult`）を集計して算出する

## 9. Composition（作文）

`Word` と同様に `Lesson` に従属しない独立エンティティ。学習者が英作文を書き溜め、
AI 添削（修正英文＋母語解説）を受ける（仕様書3.4章）。作文本文・添削結果とも端末ローカルに
保存する（サーバは添削の通信ログのみ保持し、本文・結果は保存しない）。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| englishText | String | 学習者が書いた英文 |
| japaneseText | String | 対応する日本語（訳 or 日本語での説明＝伝えたかった意図）。添削の方向を確定させるため AI に渡す |
| createdAt | Date | 作成日時 |
| updatedAt | Date | 本文編集のたびに更新。`feedback.generatedAt` との比較で「添削が古い」判定に使う |
| explanationLanguage | String | 解説言語（実質 "ja"。生成時のユーザー母語設定を記録） |
| feedback | WritingFeedback? | 旧データ（単発添削）の直近結果。v2 以降は書き込まず `rounds` を使う。ストアから外さないため残置（削除するとマイグレーションで開けなくなる恐れ）。未添削なら nil |
| roundsStorage | [WritingRound]? | 改善のやり取りの履歴（古い順）の実ストレージ。computed `rounds` 経由で参照する |

- 入力は englishText / japaneseText の**2フィールド必須**。両方が埋まるまで添削は実行できない。
- **反復改善（ラウンド式）**: 「Review」を押すたびに現在の下書き（英文＋意図）とその添削を1ラウンドとして
  `rounds` に積む。再添削時は過去の全ラウンド（英文・修正・解説）を history として AI に渡し、文脈を
  踏まえて改善を続けられる。エディタの英文は添削後も学習者が書いたまま維持し、自分で手直しして再送する。
- `rounds`（computed）: `roundsStorage` が空でも旧データ（単一 `feedback`）があれば、それを Round 1 として
  見せる（破壊的マイグレーション不要）。新ラウンド追記時に旧 feedback は Round 1 として実体化される。
- 送信可否: 英日とも非空、**かつ**下書きが最終ラウンドと相違（同一なら送る変更が無いので無効）。
  編集のたびに `updatedAt` を更新する（一覧の並び順・「編集中」バッジに使う）。
- 本文も添削も無い空の作文は残さず破棄する（新規作成後に何も書かずに離脱した場合）。

### WritingRound / WritingFeedback（埋め込み構造体）

`WritingRound` は1回分の添削ラウンド（学習者が送った英文＋意図＋その添削）。`WritingFeedback` は添削結果で、
バックエンド `/api/writing-feedback` のレスポンス `feedback` と同構造（`backend/src/writingFeedback.ts`）。
フィールドを増減する場合は iOS・backend 両方を合わせる。

**WritingRound**

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | ラウンド識別子 |
| englishText | String | このラウンドで学習者が送った英文 |
| japaneseText | String | このラウンドで学習者が送った日本語（伝えたかった意図） |
| feedback | WritingFeedback | このラウンドの添削結果 |
| createdAt | Date | ラウンド作成日時 |

**WritingFeedback**

| フィールド | 型 | 説明 |
|---|---|---|
| correctedText | String | 修正後の英文（全文） |
| explanation | String | 解説言語での解説（どこをなぜ直したか。Markdown 箇条書き） |
| model | String | 生成に使ったモデル |
| generatedAt | Date | 生成日時 |

> 埋め込み Codable は SwiftData が実プロパティ名ベースで管理するため CodingKeys は付けない
> （リネームすると値が黙って未永続化になる。`WordReviewState` と同方針）。`rounds` を格納する
> `roundsStorage` は**必ず optional で追加**する（非オプショナル追加はストアが開けなくなる）。

## 10. 今後の検討事項

- 間隔反復アルゴリズムを SM-2 / FSRS へ差し替える場合、`WordReviewState` への
  アルゴリズム固有パラメータ（easeFactor 等）の追加が必要
- 復習履歴のグラフ化等が必要になった時点で、解答1回分の記録エンティティ
  `WordReviewLog`（word / answeredAt / isCorrect / stepIndex）の追加を検討
- 対応言語リスト確定後、`translationLanguage` 等の言語コード値域を確定する
- 通信ログ（仕様書5.2章: トークン数・コスト等）は管理画面向けのバックエンド側データのため、
  本資料（iOSローカルモデル）の対象外。別途バックエンド側のスキーマとして検討する
