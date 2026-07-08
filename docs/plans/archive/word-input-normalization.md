# 単語入力の自動正規化（原形化・綴り訂正）

TODO「単語登録 / 間違った単語を登録したあときの処理」「過去形や複数形を入れた場合の処理」を
統合したプラン。両者は本質的に **「入力語を辞書見出し語（lemma）へ正規化する」同一の操作** なので、
1 つの仕組みで扱う。

## 目的・背景

現状、単語登録は入力テキストをそのまま見出し語（`Word.text`）として保存する。

- **過去形・複数形**: `ran` を入れると `ran` のまま登録され、`run` とは別語になる。ESL 語彙リストは
  原形（辞書見出し語）で持つのが自然で、変化形は AI 情報の `inflections` 側に入るべき。
- **綴り間違い**: `recieve` `apel` のような誤入力もそのまま登録され、AI 情報・クイズ・イラストまで
  誤った語で生成されてしまう（`word.text` をキーに派生生成が連鎖するため無駄が大きい）。

そこで、**登録・派生生成の前に**入力語を正規化（原形化 / 綴り訂正）し、ユーザー確認を挟む仕組みを入れる。

### 現状フロー（調査結果）

| 層 | 該当 | 備考 |
|---|---|---|
| 手動登録 | `WordAddView.swift` | `duplicateMessage`（`:102`）で同綴り完全一致の重複のみ弾く。`ran`↔`run` は別語 |
| タップ登録 | `TappableEnglishText.swift` の `WordRegistrationModifier`（`:113`） | 既に `confirmationDialog`「Add to word list?」あり。差し込み口に最適 |
| 登録の共通処理 | `WordRegistrar.register`（`WordRegistrar.swift:23`） | `Word(text:)` 生成→レッスン紐付け→保存→AI 生成トリガ。両経路が集約 |
| AI 情報生成 | backend `POST /api/word-info`（`index.ts:321`）→ `generateWordInfo`（`wordInfo.ts:155`） | Claude structured output。`inflections`（原形→変化形）はあるが**逆方向は無い** |
| モデル | `claude-haiku-4-5`（`config.ts:8`） | 安価・高速 |

正規化の逆引き機能は**現状どこにも存在しない**。AI はバックエンドにしかないため、正規化は
バックエンド呼び出しになる。

## 対応方針

### 1. 確定した UX（ユーザー決定済み）

入力語を正規化できた場合、**自動で原形/正しい綴りへ直した状態を提示**し、**なぜ直したかの説明**を
添えて、ユーザーがボタンで確定する。誤検出への保険として「入力のまま登録」の逃げ道も残す。

```
入力: ran
────────────────────────────
✏️ 原形の「run」で登録します
   「ran」は動詞「run」の過去形です   ← 母語で説明
────────────────────────────
     [ run で登録 ]     ← 主ボタン（正規化形）
     「ran」のまま登録    ← 逃げ道（入力形）
     Cancel
```

- 適用範囲: **Add Word フォーム + 英文タップ登録の両方**。
- 入力が既に見出し語（`canonical`）なら確認を出さず、従来どおり即登録。
- 正規化形が既存単語と一致したら **重複扱い**（新規作成せず既存語へ集約 / 詳細へ遷移）。
  → `ran`→`run` で既存 `run` があれば重複に倒せる（直近の重複弾き機能の自然な拡張）。
- 正規化サービスが失敗（オフライン等）したら **入力のまま登録にフォールバック**（登録をブロックしない）。

### 2. なぜ「別エンドポイントの事前チェック」か（word-info に相乗りしない理由）

- `word.text` は AI 情報・クイズ・イラスト・backend キャッシュ（`UNIQUE(word,target_language)`）の
  **identity キー**。誤った語で作ってから直すと、リネーム/マージが広範囲に波及する。
- 正規化を**登録前**に行えば、正しい語で 1 回だけ派生生成でき、原形での重複判定もできる。
- 正規化は小さなタスクなので安価・低レイテンシな haiku 単発で足りる（入力単位でキャッシュ）。

### 3. 正規化の出力仕様

`status` で分岐する：

| status | 意味 | lemma | 確認UIを出す |
|---|---|---|---|
| `canonical` | 既に見出し語 | 入力と同じ | 出さない（即登録） |
| `inflected` | 語形変化（過去形/複数形/比較級等） | 原形 | 出す |
| `misspelled` | 綴り間違い | 正しい綴り | 出す |
| `proper_noun` | 固有名詞（人名等） | 入力と同じ | 出さない（訂正しない） |
| `phrase` | 複数語の連語 | 入力と同じ | 出さない |
| `unknown` | 判定不能・英語でない | 入力と同じ | 出さない |

`reason` は母語（`targetLanguage`）で「なぜ直したか」を 1 文で返す。

## 影響範囲

### backend（Node/TS + Express + better-sqlite3 + Anthropic SDK）
- `backend/src/config.ts` — `wordNormalizeModel`（既定 `claude-haiku-4-5`）を追加。
- `backend/src/wordNormalize.ts` — **新規**。schema + `normalizeWord(word, targetLanguage)`。
  `wordInfo.ts` / `callStructured`（`ocrTranslate.ts:56`）と同じ流儀。
- `backend/src/db.ts` — キャッシュ表 `word_normalizations`（`UNIQUE(input, target_language)`）と
  ログ表 `word_normalize_requests`（`word_info_requests` を踏襲、コスト集計用）+ get/upsert/log ヘルパ。
- `backend/src/index.ts` — `POST /api/word-normalize`（バリデーション→キャッシュ→生成→ログ→返却）。
- `backend/src/admin.ts` — `/admin/word-normalize` 一覧/詳細・ナビ・`/admin/usage` の利用元表示に追加。

### iOS（SwiftUI + SwiftData）
- `Sources/Models/WordNormalization.swift` — **新規**。`{ input, lemma, status, reason }` の Codable（**永続化しない**トランジェント）。
- `Sources/Services/RemoteWordNormalizeService.swift` — **新規**。`RemoteWordInfoService` に倣い `POST api/word-normalize`。
- `Sources/Views/WordAddView.swift` — Add 押下で正規化→確認 UI（逃げ道・原形 dedup・ローディング・失敗フォールバック）。
- `Sources/Views/TappableEnglishText.swift`（`WordRegistrationModifier`）— 既存 `confirmationDialog` を拡張。
- `WordRegistrar.register` は**変更しない**（確定した text を渡す最終プリミティブのまま）。
- iOS は XcodeGen 管理のため新規ファイルは `xcodegen generate` で再生成（pbxproj は手編集しない）。

## Phase / Step

- **Phase 0: backend 正規化エンドポイント**
  - config / `wordNormalize.ts`（schema + 生成）/ db（キャッシュ+ログ）/ `/api/word-normalize` / admin
  - curl で `ran`→`run`(inflected), `recieve`→`receive`(misspelled), `apple`→canonical を確認
- **Phase 1: iOS 正規化サービス・モデル**
  - `WordNormalization` モデル + `WordNormalizeService`/`RemoteWordNormalizeService`（+ 単体テスト）
- **Phase 2: Add Word フォーム統合**
  - Add 押下 async 正規化 → 確認 UI（主=正規化形 / 逃げ道=入力形 / Cancel）
  - 正規化形が既存語と一致 → 重複メッセージ・既存へ集約 / 失敗時フォールバック / ローディング表示
- **Phase 3: 英文タップ登録統合**
  - `WordRegistrationModifier.handleTap` を async 正規化経由に。確認ダイアログに説明＋原形ボタン＋
    「入力のまま」＋Cancel。正規化形が既存 → 既存詳細へ遷移（dedup）
- **Phase 4: 既登録の誤り修正（リネーム＋マージ）** ← 影響精査のうえ実装決定（2026-07-07）
  - TODO 表題「登録した**あと**の処理」に対応。`WordDetailView` から再正規化してリネーム/マージする。

  ### 精査結果（波及マップ）
  `Word.text` は **DB キーではない**（SwiftData の identity は `Word.id`／UUID）。同綴り判定は
  アプリ内の大小無視文字列比較のみ。ただし `text` は次の**キャッシュキー**で、リネームすると
  旧キーの生成物は孤児化し、新キーで**キャッシュミス→再生成**される（＝自己修復・移行不要）。
  - backend: `words`(AI情報, UNIQUE(word,lang)) / `quiz_questions`(UNIQUE(word,lang,format,variant)) /
    `word_illustrations`(key_hash=sha256(model|word|lang|sense)) / `tts_audio`(sha256(model|text))。
    いずれも `normalizeWordKey(word)=trim+lowercase` でキー化。旧行は放置（アプリからの削除APIは無い）。
  - iOS: イラスト PNG（同じ sha256 キー）/ 単語発音 WAV（sha256(model|text)）はローカルでも孤児化＆再生成。
  - クイズ問題はローカル非永続（毎セッション `word.text` で取得）。次セッションで新キーで取得→backend 再生成。
  - **Word 行上の値**（`reviewState`・`occurrences`）は行に属するのでその場リネームで**保持される**。
  - 一方 `translation`/`partOfSpeech`/`grammarNote`/`exampleSentence`/`aiInfo` は**旧綴りの内容**なので
    リネーム時にクリアして作り直す。特に `translation` は空でないと `WordAIInfoGenerator` が上書きしない。

  ### 実装設計
  - `WordRegistrar.correct(_ word:to:in:existingWords:regenerateAIInfo:) -> CorrectionOutcome?`（新プリミティブ）
    - **完全一致**（trim後 text と同じ）→ nil（何もしない）。
    - **大小のみ違い** → 派生情報は有効なので `text` だけ整えて `.renamedInPlace`（再生成しない）。
    - **衝突なし** → その場で `word.text=lemma`、旧綴り由来の派生情報をクリア、`saveOrLog`、
      `WordAIInfoGenerator.generateInBackground(for:)` で AI 情報を作り直す（成功時にクイズ・イラストも連鎖）。→ `.renamedInPlace`
    - **衝突あり**（`lemma` が自分以外の既存語と大小無視一致）→ 出現を既存語へ付け替え、
      既存語に同一 (lesson, sourcePhoto, sourceAudio) があれば重複を作らず削除（`link` と同じ dedup）、
      元の Word 行を削除。`reviewState`/`aiInfo`/`translation` は**既存語のもの**を維持。→ `.mergedInto(既存語)`
  - `WordDetailView` の Actions セクションに「Correct Word」を追加。押下で `RemoteWordNormalizeService` に
    `word.text` を投げ、`requiresConfirmation`（inflected/misspelled かつ lemma≠現綴り）なら確認ダイアログ
    （主=「Correct to “lemma”」＋説明 reason／Cancel）、そうでなければ「already looks correct」を告知。
    確定時 `WordRegistrar.correct` を実行し、`.mergedInto` は `dismiss()`（表示中の語が消えるため一覧へ戻る）、
    `.renamedInPlace` はその場に留まる（タイトル・各セクションが新綴り／再生成中表示に更新）。
  - `WordRegistrar.register`（登録の最終プリミティブ）は**変更しない**。
  - テスト: `WordRegistrarTests` に correct の5ケース（リネーム／マージ／dedup／no-op／大小のみ）を追加。

## テスト方針
- backend: 主要 status（inflected/misspelled/canonical/proper_noun/phrase/unknown）を curl で確認。
  キャッシュ命中・コストログ・`/admin/usage` 反映を確認。
- iOS: `WordNormalizeService` をフェイク差し替えして、
  - 確認 UI の出し分け（canonical=出さない / inflected・misspelled=出す）
  - 主ボタンで原形登録 / 逃げ道で入力形登録
  - 正規化形が既存語 → 重複集約
  - サービス失敗 → 入力のまま登録（フォールバック）
  を UI/単体テストで検証。既存 `WordAddDuplicateUITests` と整合を取る。

## 未確定・留意点
- Phase 4 の既登録修正（リネーム波及）は影響が大きいため実装可否は後日判断。
- 正規化の追加 AI 呼び出しはコスト・レイテンシ増だが、haiku 単発＋入力単位キャッシュで許容範囲。
- 逃げ道で変化形/誤綴りを登録した場合の派生生成はその語で走る（従来どおり）。
