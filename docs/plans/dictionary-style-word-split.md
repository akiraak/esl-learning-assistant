# 多義語の辞書式分割（意味クラスタごとに別単語エントリ）

## 目的・背景

- 例: `fall` を追加すると単語一覧に「秋」とだけ表示され、「落ちる」の意味だと分からない。
  現状 `Word.translation` は先頭語義（`senses.first.meaning`）1件だけを自動補完している
  （`WordAIInfoGenerator.swift:51`）ため、多義語で意味が伝わらない。
- 単純に「品詞（名詞/動詞）で分ける」案は不適。品詞は「意味が別かどうか」の軸として当てにならない。
  - **分けなさすぎ**（同一品詞で別意味）: `bank`＝銀行/川岸、`letter`＝手紙/文字、`spring`＝春/ばね/泉、
    `run`＝走る/経営する。品詞で割っても同じ破綻（意味が分からない・イラストが1枚で描けない）が残る。
  - **分けすぎ**（品詞違いだが同義）: `rain`＝雨/雨が降る、`water`＝水/水をやる、`walk`＝散歩/歩く。
    品詞転換語を機械的に割ると冗長なカードが増える。
- 本当に効く軸は**「意味のまとまり（同綴異義＝辞書の別見出し語）」**。辞書は品詞では見出しを割らず、
  語源・意味が無関係なものだけ別見出しにする。分割基準の直感テストは
  **「1枚の絵で両方を教えられるか？」**（教えられない＝別エントリ）。
- 判定は既に呼んでいる AI（word-info 生成）に委ねる。`fall`→「落ちる」群/「秋」群の2エントリ、
  `bank`→「銀行」群/「川岸」群の2エントリ、`rain`→1エントリ、のように分ける。
  品詞は「分割軸」ではなく各行の**表示ラベル**に降格する。

## 対応方針

### データモデル
- `Word` に **optional な判別子** `var senseGroupKey: String?` を追加する。
  - 非オプショナル追加は SwiftData のライトウェイトマイグレーションを壊す既知の地雷
    （`docs/plans/archive/fix-reviewstate-migration-failure.md`、`Word.swift:16-17,126-160` のコメント）。
    必ず nullable カラム（optional + 既定 nil）にする。埋め込み Codable 側に入れない。CodingKeys リネーム禁止。
  - 単語の同一性が実質 `text` から `(text, senseGroupKey)` に変わる。
- 一覧に同一 `text` の複数行が出るのを許容する（`WordsView` は表示側の対応で語義ラベルを添える）。

### バックエンド（AI グループ判定）
- `WORD_INFO_SCHEMA`（`backend/src/wordInfo.ts:6-124`）に見出しクラスタの構造を追加する。
  案: 各 sense に整数 `homographGroup` を持たせる（最小変更）か、`entries[]` で senses をグループ化する。
  - 構造化出力は array の minItems/maxItems 非対応（`wordInfo.ts:9-10`）。件数・分割基準は description で指示する。
  - 分割基準をプロンプトに明記：「語源・意味が無関係な同綴異義のみ別グループ。関連多義（例 run の各語義）は
    同一グループに保つ」。過分割を抑制する。
- iOS 側 `WordAIInfo`（`Word.swift:66-119`）を同じ構造に同期する（`wordInfo.ts:4,64` の同期要件）。
- word-info の DB キャッシュは `(word, target_language)` の1ブロブのまま変更不要
  （グループはブロブ内に入る、`db.ts:375-410`）。
- モデルは既定 `claude-haiku-4-5`（`config.ts:8`）。クラスタリング精度が不足する場合は
  `ANTHROPIC_WORD_INFO_MODEL` を上位モデルに切替（env のみ、コード変更不要）。

### 生成フローで分割生成
- `WordAIInfoGenerator.generate(for:)`（`WordAIInfoGenerator.swift:22-71`）を拡張：
  - 応答のグループ0（文脈に合う先頭クラスタ）を渡された `word` に反映。
  - 追加クラスタごとに `Word(text:...)` を作り `word.modelContext?.insert(newWord)` → `saveOrLog()`。
    `PersistentModel.modelContext` は挿入済みモデルで取得可能（全呼び出し元が挿入済み `word` を渡す）。
  - 各エントリの `translation` はそのグループの意味で埋め、`senseGroupKey` を設定。
  - レッスン由来の `WordOccurrence` は、OCR 文脈（`WordAIInfoGenerator.swift:29-34` で取得済み）に
    合致するクラスタのエントリに付け替える（文脈に合う語義へ紐付け）。

### 追加フロー・重複判定
- 追加 UI は見出し語のみ入力（`WordAddView.swift:26`）。語義セレクタは無いので、分割は生成後に行う方針。
- 重複判定 `WordAddView.addWord`（`WordAddView.swift:83-90`）：ベースエントリ単位で再利用し、
  分割はジェネレータに委ねる。
- `ReviewSessionView.swift:734` の `text` ルックアップは `word.id` ベースに変更（同綴で誤マッチを防ぐ）。

### イラスト（語義ごと）
- キーは既に `sha256(model|word|language|senseIndex)` で **API・DB・クライアントに貫通済み**
  （`WordIllustrationStore.swift:19-23`、`index.ts:540-543`、`db.ts:117-133`）。
  現状すべての呼び出しが `senseIndex: 0` 固定（`WordIllustrationGenerator.swift:23,33,42,44`、
  `WordDetailView.swift:518`、`ReviewSessionView.swift:740`）。
- `Word` の `senseGroupKey` → 安定した Int（senseIndex）へマップして各呼び出しに渡す。
  in-flight 排他 Set / 失敗 dict も自動で語義ごとになる。バックエンド・ストア・ハッシュは無変更。

### TTS
- 変更不要。発話テキスト＋モデルでキャッシュ（`TTSAudioStore.swift:15-18`）。
  同綴の "fall" が同じ音声を共有するのは正しい挙動。判別子を足さない。

### クイズ（語義ごと）— 最重量
- 現状キーは `(word, target_language, format, variant_index)` で判別子なし
  （`db.ts:176-191`）。再生成の delete→insert（`db.ts:627-646`）が同綴の**兄弟エントリの問題を消す**。
- 変更内容：
  - DB: `quiz_questions` の UNIQUE キーにグループ判別子を追加し、
    `replaceQuizQuestions`/`listQuizQuestions`/`countQuizQuestions`/delete stmt をグループスコープ化。
  - API: `/api/quiz-questions/generate`・`/query` のリクエストに判別子を追加。`/query` レスポンスを
    語義ごとにアドレス可能な形へ（現在は正規化テキストキーの dict）。
  - プロンプト: `buildPrompt`（`quizQuestions.ts:479`）に該当グループの senses のみ渡す。
  - クライアント: `RemoteQuizQuestionService`（`RemoteQuizQuestionService.swift:11-14,41-45`）と
    `ReviewSessionView.swift:557-568` のマッピングを `word.id`／判別子ベースへ。

### 既存データの遡及対応
- Regenerate ボタン（`WordDetailView.swift:88-97,133-144`）が自然なフック。生成拡張により再生成時に分割する。
- 全ストア一括の移行処理は作らない。各単語は Regenerate 実行時に分割される（既存の単一ブロブ Word は
  再生成まで従来どおり動作）。

## 影響範囲

- iOS: `Models/Word.swift`、`Support/WordAIInfoGenerator.swift`、`Views/WordsView.swift`（行表示）、
  `Views/WordAddView.swift`、`Views/WordDetailView.swift`、`Views/ReviewSessionView.swift`、
  `Services/RemoteWordInfoService.swift`、`Services/RemoteQuizQuestionService.swift`、
  `Support/WordIllustrationGenerator.swift`、`Services/WordIllustrationStore.swift`。
- backend: `src/wordInfo.ts`（スキーマ/プロンプト）、`src/index.ts`（quiz エンドポイント）、
  `src/quizQuestions.ts`（buildPrompt/スキーマ）、`src/db.ts`（quiz_questions キー）。
- 既存テスト: `WordAIInfoTests`、`WordIllustrationStoreTests`、UI テスト
  （`LessonWordAddUITests`/`LessonWordRemoveUITests`/`WordDetailButtonsUITests`）が同綴複数行を前提に要見直し。

## Phase / Step

### Phase 1 — コア分割（一覧・イラストまで）
- [x] Step 1: backend `wordInfo.ts` にグループ構造（sense.homographGroup）＋分割基準プロンプトを追加、iOS `WordAIInfo.Sense` を同期（optional で旧ブロブ後方互換）
- [x] Step 2: `Word` に optional `senseGroupKey` を追加（migration 安全な nullable カラム）＋ `senseGroupNumber`/`groupSenses`/`illustrationSenseIndex` ヘルパ
- [x] Step 3: `WordAIInfoGenerator` を分割生成に拡張（`applySplit`：先頭グループを base、追加グループを兄弟 Word に。同 text・同 senseGroupKey は重複生成しない）
- [x] Step 4: 一覧は兄弟 Word が別行になるため訳語で自動的に判別（`WordRow` 変更不要）。`WordDetailView` の Meanings をグループ絞り込み表示に、`ReviewSessionView` の出題語イラストを `Word`/senseIndex ベースに
- [x] Step 5: イラストの `senseIndex` 0 固定を外し、`WordIllustrationGenerator`/`WordDetailView` を語義ごとに生成・表示

**Phase 1 の簡略化（要フォロー）**:
- occurrence の付け替えは未実装。生成は先頭 context を group0 に置くため、その context の occurrence は base に残り正しい。複数 context（別レッスンで別語義）の精密な付け替えは Phase 2/3 で扱う。
- クイズ生成トリガは word text 単位のまま（語義非分離）。Phase 2 で分離。
- 選択肢イラスト（distractor）は text 先頭一致で解決。同綴の一意化は Phase 2。

### Phase 2 — クイズの語義分離
- [ ] Step 1: backend `db.ts` の `quiz_questions` キーに判別子を追加し CRUD をグループスコープ化
- [ ] Step 2: quiz `/generate`・`/query` の API 契約に判別子を追加、`buildPrompt` をグループ限定に
- [ ] Step 3: クライアント `RemoteQuizQuestionService`／`ReviewSessionView` のマッピングを更新

### Phase 3 — 既存データの遡及分割
- [ ] Step 1: Regenerate を分割対応にする（再生成時に兄弟 Word を生成）

## テスト方針

- 単体: 分割生成ロジック（グループ0を既存 Word に、追加グループを新規 Word に）、`senseGroupKey`→senseIndex マップ、
  クイズキーのグループスコープ。`WordIllustrationStoreTests` に語義ごとキーのケース追加。
- マイグレーション: 既存単一ブロブ Word を持つストアで起動・再生成が壊れないこと（optional 追加の安全確認）。
- 手動/UI: `fall`・`bank`（同品詞別意味）・`rain`（分割しない）で期待どおりの行数・ラベル・イラスト・クイズになること。
  レッスン由来の `fall` が文脈語義に紐付くこと。
