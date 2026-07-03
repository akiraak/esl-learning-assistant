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
- `Word` のみ `Lesson` に従属しない独立エンティティとする（1章参照）。同じ単語が複数レッスンの
  教科書に出てきても 1つの `Word` レコードに統合され、復習状態（`reviewState`）も共有される
- 本資料は **スキーマ**を確定するもの。以下は仕様書9章に残課題として残り、本資料のスコープ外
  - 対応言語（母語）の具体的なリスト
- 単語帳の間隔反復アルゴリズムは固定ステップの Leitner 方式で確定した（§5 参照。
  策定経緯: [docs/plans/word-memorization-quiz.md](../plans/word-memorization-quiz.md)）

## 1. エンティティ関連図（概要）

```
Class 1 ── * Lesson
Lesson 1 ── * Photo
Lesson 1 ── * Question ── * (sourcePhoto: Photo?)
Question 1 ── * QuizResult

Lesson * ── * Word   (中間エンティティ WordOccurrence 経由)
WordOccurrence ── 1 Lesson
WordOccurrence ── 1 Word
WordOccurrence ── * (sourcePhoto: Photo?)
```

- `Lesson` は `Class` に必須で属する（仕様書4章: クラス／レッスンの2段階管理単位）
- `Photo` / `Question` は `Lesson` に必須で属する（仕様書4章: レッスン単位の管理）
- `Word` は `Lesson` に従属しない独立エンティティ。`Lesson` との関連は `WordOccurrence`
  （「どのレッスンでこの単語に出会ったか」の出現記録）を介した多対多とする
- `Question.sourcePhoto` / `WordOccurrence.sourcePhoto` は任意の参照（手動登録や、
  複数写真にまたがる場合等を許容するため）

### データ構造ツリー

`Class` 配下の所有階層と、`Lesson` に従属しない `Word` を別ツリーとして示す。

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
    │   └─ occurredAt
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
確定した（策定経緯: [docs/plans/word-memorization-quiz.md](../plans/word-memorization-quiz.md) §3.1）。
レッスンをまたいでも同じ単語であればこの状態を共有する（レッスンごとに復習履歴が分散しない）。

- 復習ステップ: `[3日, 7日, 14日, 30日, 90日]`（stepIndex 0〜4）。90日到達後は 90日間隔を維持
- 正解 → `dueDate = 今日 + 現在ステップの日数` とし、ステップを1つ進める（最終ステップでは維持。
  新規単語の初回正解は +3日）。
  不正解 → stepIndex 0 に戻し `dueDate = 今日 + 3日`（同日中の再出題はセッション内のみ）
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

- 既存レコードには追加フィールドをデフォルト値（0）で吸収する（SwiftData 埋め込み構造体のため
  マイグレーション不要）

## 6. WordOccurrence（出現記録）

`Word` と `Lesson` の多対多関連を表す中間エンティティ。「どのレッスンの教科書で
この単語に出会い、どの写真のOCR結果からタップ登録したか」を1件ずつ記録する。

| フィールド | 型 | 説明 |
|---|---|---|
| id | UUID | 主キー |
| word | Word | 対象単語（to-one, 必須。所有はしない参照） |
| lesson | Lesson | 出会ったレッスン（to-one, 必須） |
| sourcePhoto | Photo? | OCR結果のタップ登録の場合の参照元（手動登録時は nil） |
| occurredAt | Date | このレッスンでの登録・紐づけ日時 |

- 同一 `Word` が同一 `Lesson` で複数回タップ登録された場合も、出現履歴として複数件許容する
- `Lesson` 削除時にカスケード削除される（`Word` 側からの削除ではない限り `Word` 自体は残る）
- `Word` 削除時（ユーザーが単語帳から明示的に削除した場合）もカスケード削除される

## 7. Question（問題）

教科書内容から AI が自動生成する練習問題（仕様書3.3章）。

> **位置づけ**: `Question` / `QuizResult` は **AI 生成問題（v2、仕様書3.3章）用**のモデル。
> 単語帳の復習クイズ（仕様書3.2章）はレッスンに紐づかず問題をローカルで動的に生成するため、
> `Question` レコードは作成せず、結果は `Word.reviewState` の更新のみで記録する。

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

## 9. 今後の検討事項

- 間隔反復アルゴリズムを SM-2 / FSRS へ差し替える場合、`WordReviewState` への
  アルゴリズム固有パラメータ（easeFactor 等）の追加が必要
- 復習履歴のグラフ化等が必要になった時点で、解答1回分の記録エンティティ
  `WordReviewLog`（word / answeredAt / isCorrect / stepIndex）の追加を検討
- 対応言語リスト確定後、`translationLanguage` 等の言語コード値域を確定する
- 通信ログ（仕様書5.2章: トークン数・コスト等）は管理画面向けのバックエンド側データのため、
  本資料（iOSローカルモデル）の対象外。別途バックエンド側のスキーマとして検討する
