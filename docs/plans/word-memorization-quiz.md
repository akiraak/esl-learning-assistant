# 単語を覚える問題機能（復習クイズ）設計プラン

## 1. 目的・背景

- 単語帳（Words タブ）に登録した単語を「覚える」ための出題・復習機能を設計する。
- `docs/specs/app-spec.md` §3.2（フラッシュカード／間隔反復による復習）および §3.3（問題作成）の Phase 3 に相当する、未実装の機能。
- データモデル上は `Word.reviewState`（`WordReviewState`: dueDate / lastReviewedAt / reviewCount）が既に存在するが、どの画面からも読み書きされていない。間隔反復アルゴリズムは「別途検討」と保留されていた（`docs/specs/data-model.md` §5, §10）。本プランでそれを確定する。

## 2. 調査: 「1日後→3日後→7日後」と間隔を伸ばす方式は本当に有効か

TODO の疑問「記憶は1日後3日後7日後と間を伸ばしてテストすると覚えやすいと聞いたけどそれは確かか？」への回答。

### 結論（要約）

**「間隔を空けて、テスト形式で復習する」こと自体の効果は科学的に非常に確か。ただし「間隔を徐々に広げる（拡張間隔）」ことが「等間隔」より優れるという証拠は弱い。** 実用上は復習回数を抑えられる拡張間隔が合理的で、Anki 等のデファクト方式でもある。

### 根拠

1. **分散効果（spacing effect）は極めて頑健**。Cepeda ら (2006) のメタ分析（317実験・839評価）で、まとめて学習するより間隔を空けた方が長期保持が大きく向上することが確認されている。語彙学習を含む第二言語学習でも Kim & Webb (2022) のメタ分析で効果が支持されている。
2. **テスト効果（retrieval practice）も頑健**。見直すだけより「思い出させるテスト」の方が長期記憶に残る。クイズ形式にすること自体に強い根拠がある。
3. **一方「拡張間隔 vs 等間隔」は決定的な差がない**。Karpicke & Roediger (2007) は、拡張間隔は直後のテストでは有利だが、2日後の遅延テストでは等間隔の方が優れる逆転を報告。その後の研究（Kang ら 2014 等）でも長期では大差なし〜等間隔優位が混在。重要なのは間隔の形状より「最初の復習をある程度遅らせること」「想起させること」。
4. **最適な間隔は「いつまで覚えていたいか」に依存**する（Cepeda ら 2006/2008）。保持したい期間が長いほど復習間隔も長くとるべき。
5. **実用システムの知見**: Anki の SM-2 や後継の FSRS は拡張間隔ベース。FSRS は7億件超の実レビューデータのベンチマークで SM-2 より想起予測が正確（同じ定着率で復習回数 20〜30% 減）とされる。ただし個人パラメータ学習が必要で v1 には過剰。

### 設計への示唆

- 「1日→3日→7日→…」の固定拡張スケジュールは、**理論的に最適だからではなく、復習負荷を有界に保ちつつ分散効果とテスト効果を確実に得られる実用解**として採用してよい。厳密な間隔の形は成績への影響が小さいため、シンプルな固定ステップで十分。
- 効果の本体は「クイズ形式（想起）」+「間隔を空ける」の2点。ここを外さないことを最優先にする。

参考: [Cepeda et al. 2006 メタ分析](https://augmentingcognition.com/assets/Cepeda2006.pdf) / [Karpicke & Roediger 2007](https://learninglab.psych.purdue.edu/downloads/2007/2007_Karpicke_Roediger_JEPLMC.pdf) / [Kang et al. 2014](https://link.springer.com/article/10.3758/s13423-014-0636-z) / [Kim & Webb 2022 (L2メタ分析)](https://onlinelibrary.wiley.com/doi/abs/10.1111/lang.12479) / [open-spaced-repetition/srs-benchmark](https://github.com/open-spaced-repetition/srs-benchmark)

## 3. 対応方針（設計）

### 3.1 間隔反復アルゴリズム（v1: 固定ステップの Leitner 方式）

- 復習ステップ: `[3日, 7日, 14日, 30日, 90日]`（step 0〜4）。90日到達後は 90日間隔を維持（または「習得済み」扱い）。
- 正解 → `dueDate = 今日 + 現在ステップの日数` とし、ステップを1つ進める（最終ステップでは維持）。
  新規単語（step 0）の初回正解は +3日となり、以降 7日→14日→… と広がる。
- 不正解 → step 0 に戻し、`dueDate = 今日 + 3日`（同日中の再出題はセッション内のみ）。
- 新規登録語は `dueDate = 登録日`（当日から出題対象）。
- 判定はローカル日付（Calendar）基準。`dueDate <= 今日` の単語が「今日の復習」対象。
- SM-2 / FSRS への将来移行を見越し、アルゴリズムは `ReviewScheduler` としてモデルから分離した純関数で実装する（差し替え可能に）。

### 3.2 `WordReviewState` の拡張

既存フィールドに以下を追加（SwiftData 埋め込み構造体なのでマイグレーションはデフォルト値で吸収）:

| フィールド | 型 | 説明 |
| --- | --- | --- |
| stepIndex | Int | 現在の復習ステップ（初期値 0） |
| correctCount | Int | 累計正解数（初期値 0） |
| lapseCount | Int | 不正解でリセットされた回数（初期値 0） |

`docs/specs/data-model.md` §5・§10 も合わせて更新する。

### 3.3 出題形式（v1 はローカル生成、AI 不要）

**方針（確定）**:

- **問題文・選択肢はすべて英語**。日本語 translation は問題には使わない（正解後のフィードバック表示にのみ使用可）。
- **音声問題を約半分（50%）混ぜる**。音声は既存の TTS 基盤（`GeminiSpeechService` + `TTSAudioStore`、フォールバックに `AVSpeechSynthesizer`）を利用。
- 自己評価形式は採用しない。正誤が客観的に決まる形式のみ。
- 素材は `Word` + `WordAIInfo`（englishDefinition / examples / synonyms / antonyms / collocations / inflections / IPA）からローカル生成する。`aiInfo` が未生成の単語は、`text` だけで組める形式（TC9・VC2・VT1 など）に自動フォールバックする。
- 誤答選択肢は原則、単語帳内の他の単語（品詞・CEFR が近いものを優先）から取る。登録語が少なく選択肢が組めない場合も同様に `text` のみ形式へフォールバック。
- イラストを使う形式（TC11・IC1・IT1・VC8）はイラスト生成済みの単語に限って出題する。イラスト4択（TC11・VC8）は誤答用に他単語の生成済みイラストが3枚以上必要で、足りない場合はテキスト系形式へフォールバック。
- **品詞・活用形ラベルの日→英マッピングが必要**: `Sense.partOfSpeech`・`Inflection.form` は母語（日本語）表記で保存されている（例:「動詞」「過去形」）ため、全英語の問題文（TC7・TC8・TT3・VC7）に使うには「動詞 → verb」「過去形 → past tense」等の固定マッピングテーブルを実装する。マッピングに無いラベルの単語では該当形式を出題しない（フォールバック）。

**形式 ID の表記ルール**: `[出題][回答] + 連番`。

- モダリティ文字: **T** = テキスト、**V** = 音声、**I** = イラスト、**C** = 4択（choice、回答のみ）
- 接頭辞の末尾が回答タイプ。例: **TC** = 出題テキスト・回答4択、**TT** = 出題テキスト・回答テキスト入力、**VT** = 出題音声・回答テキスト入力、**TV** = 出題テキスト・回答音声入力
- 出題が複合の場合は連結する: **VTC** = 出題が音声+テキスト・回答4択
- 4択（C）の選択肢はテキストのほかイラストも可（TC11・VC8 はイラスト4択）
- 評価方法は「一致 / 一致率 / 発音スコア / LLM 判定」の4種。4択・テキスト入力系は「一致」（例文を書き取る VT2 のみ「一致率」）で、発音スコア / LLM 判定は音声入力系（§7.1）にのみ登場する

**採用形式（確定）: TC1〜TC11・TT1〜TT3・IC1・IT1・VC1〜VC8・VTC1・VTT1・VT1〜VT2 の28形式**（「部分スペル入力」は不採用）

TC: 出題テキスト・回答4択（評価: 一致）:

| # | 形式 | 問題文 → 回答 | 必要データ |
| --- | --- | --- | --- |
| TC1 | 定義→単語 | 英語定義を提示 → 単語を選ぶ | englishDefinition |
| TC2 | 単語→定義 | 単語を提示 → 正しい英語定義を選ぶ（誤答は他単語の定義） | englishDefinition |
| TC3 | 例文穴埋め | 例文の対象語を空所にして提示 → 入る単語を選ぶ | examples |
| TC4 | 類義語 | "Which is closest in meaning to X?" → synonym を選ぶ | synonyms |
| TC5 | 対義語 | "Which is the opposite of X?" → antonym を選ぶ | antonyms |
| TC6 | コロケーション | "make a ___ / ___ a decision" 等、コロケーションの空所に入る語を選ぶ | collocations |
| TC7 | 活用形 | "What is the past tense / plural of X?" → 正しい活用形を選ぶ（誤答は規則活用の誤形など） | inflections |
| TC8 | 品詞 | "X is a ___ (noun / verb / adjective / adverb)" | partOfSpeech |
| TC9 | スペリング | 正しい綴りを選ぶ（誤答は文字入替・脱字で機械生成） | text のみ |
| TC10 | 文中語義 | 例文を提示し "What does X mean here?" → 定義を選ぶ。例文と語義の対応がデータモデルに無いため、**v1 は senses が1件の単語に限定**（誤答は他単語の定義）。多義語対応は Example↔Sense リンクの追加後（スコープ外） | examples + senses |
| TC11 | 単語→イラスト4択 | 単語を提示 → 対応するイラストを4枚から選ぶ（誤答は他単語の生成済みイラスト） | 単語イラスト |

TT: 出題テキスト・回答テキスト入力 / IC: 出題イラスト・回答4択 / IT: 出題イラスト・回答テキスト入力（いずれも評価: 一致）:

| # | 形式 | 問題文 → 回答 | 必要データ |
| --- | --- | --- | --- |
| TT1 | 定義→単語入力 | 英語定義を提示 → 単語をタイプ入力（TC1 の入力版。4択より想起強度が高い） | englishDefinition |
| TT2 | 例文穴埋め入力 | 例文の対象語を空所にして提示 → 入る単語をタイプ入力（TC3 の入力版） | examples |
| TT3 | 活用形入力 | "Type the past tense of X" → 活用形をタイプ入力（TC7 の入力版） | inflections |
| IC1 | イラスト→単語 | 単語イラストだけを表示 → 単語を4択で選ぶ | 単語イラスト |
| IT1 | イラスト→単語入力 | 単語イラストだけを表示 → 単語をタイプ入力 | 単語イラスト |

VC: 出題音声・回答4択 / VTC: 出題音声+テキスト・回答4択 / VTT: 出題音声+テキスト・回答テキスト入力 / VT: 出題音声・回答テキスト入力（評価は VT2 のみ「一致率」、他は「一致」。再生ボタンで繰り返し再生可）:

| # | 形式 | 問題文 → 回答 | 必要データ |
| --- | --- | --- | --- |
| VC1 | 音声→定義 | 単語の音声を再生 → 正しい英語定義を選ぶ | TTS + englishDefinition |
| VC2 | 音声→綴り | 単語の音声を再生 → 正しい綴りを選ぶ（誤答は類似綴りの他単語 or 機械生成ミススペル） | TTS + text |
| VC3 | 定義音声→単語 | 英語定義を音声で再生 → 該当する単語を選ぶ | TTS + englishDefinition |
| VC4 | 例文リスニング→単語特定 | 例文音声のみ再生（文は非表示）→ 「どの登録単語が聞こえたか」を4択 | TTS + examples |
| VC5 | 類似音判別 | 単語音声を再生 → 発音の近い語（編集距離で選出）と混ぜた4択から聞こえた語を選ぶ | TTS + text |
| VC6 | 例文聞き分け | 例文音声を再生 → 聞こえた文を4つの類似文（他単語の例文等）から選ぶ | TTS + examples |
| VC7 | 活用形リスニング | 活用形の音声を再生 → 「どの形か」（base / past / plural…）または元の単語を4択 | TTS + inflections |
| VC8 | 音声→イラスト4択 | 単語の音声を再生 → 対応するイラストを4枚から選ぶ | TTS + 単語イラスト |
| VTC1 | 例文リスニング穴埋め | 例文音声を再生し、画面には対象語を空所にした文 → 入る単語を4択 | TTS + examples |
| VTT1 | 例文リスニング穴埋め入力 | 例文音声を再生し、画面には対象語を空所にした文 → 入る単語をタイプ入力（VTC1 の入力版） | TTS + examples |
| VT1 | 単語ディクテーション | 単語の音声を再生 → テキスト入力で綴る（完全一致で判定、大文字小文字無視） | TTS + text |
| VT2 | 例文ディクテーション | 例文音声を再生（文は非表示）→ 聞こえた文全体をタイプ入力（正規化後、単語単位の一致率で判定） | TTS + examples |

**出題形式の選定と比率調整（確定）**:

- 形式プールは「読んで→テキスト4択」に偏っている（28形式中、回答の 68% がテキスト4択・タイプ入力 25%・イラスト系 7%）ため、単純ランダムではなく**目標比率に基づく重み付き選定**を行う。
- 目標比率（v1 既定値、`FormatRatioTargets` 定数として定義）:
  - **出題モダリティ**: テキスト 50% / 音声 50%（複合出題 VTC1・VTT1 は音声側にカウント）。イラスト出題（IC1・IT1）は素材のある単語で全体の 10% を目安に混入し、テキスト枠から充当する。
  - **回答モダリティ**: 4択 60% / タイプ入力 30% / イラスト4択 10%。イラスト4択（TC11・VC8）は誤答用イラストが揃う場合のみ。
- 選定アルゴリズム: セッションの各問で「現時点までの実績比率と目標比率の乖離が最大の枠」を優先し、その枠を満たせる形式を単語の利用可能プールから選ぶ（貪欲法）。純関数 `FormatSelector.select(availableFormats:sessionCounts:targets:)` として `ReviewScheduler` と同様にモデルから分離して実装する。
- フォールバック: 単語のデータ不足（aiInfo 未生成・イラスト未生成・登録語数不足）で目標枠の形式が組めない場合は、比率より出題可能性を優先して他の枠から選ぶ。比率はセッション単位のベストエフォートとする。
- 目標比率は v1 ではコード内定数。設定画面での調整や弱点重視（正答率の低い形式・モダリティを厚くする）は将来検討（スコープ外）。
- v2 以降で AI 生成問題（空所補充・並べ替え、`docs/specs/app-spec.md` §3.3 の `QuestionType`）を `POST /api/quiz` として追加する。実装時は `wordInfo.ts` の `callStructured` + JSON スキーマのパターンを踏襲。**v2 は本プランのスコープ外**。
- 音声入力（発話して回答する）形式は §7 の調査結果を参照（候補 TV1〜TV8・IV1・VV1・VTV1）。v1 スコープ外だが、グループ1（TV1〜TV5・IV1・VV1・VTV1、発話回答型）はオンデバイス音声認識で追加コストなしに v1.x で追加できる見込み。

### 3.4 結果の記録

- スペックの `Question` / `QuizResult` はレッスン紐付け（Lesson 1─* Question）で、単語帳ベースの復習クイズとはライフサイクルが合わない。v1 では `Question` モデルは作らず、**動的に出題し結果は `Word.reviewState` の更新のみで記録**する。
- 履歴のグラフ化等が必要になった時点で `WordReviewLog`（word / answeredAt / isCorrect / stepIndex）の追加を検討（スコープ外）。
- `data-model.md` §7–8 の `Question`/`QuizResult` は「AI 生成問題（v2）用」と位置づけを注記する。

### 3.5 画面設計（iOS / SwiftUI）

- **問題開始の導線（確定）**: Words タブ上部の「今日の復習」カードから開始する。加えて Words タブのタブアイコンに復習対象件数をバッジ表示（`.badge(count)`）し、起動直後に復習の有無が分かるようにする。専用 Review タブへの昇格は利用が定着してから検討（スコープ外）。WordDetailView からの単発出題も、スケジュール外出題で間隔がずれる問題があるため v1 では入れない。
- **Words タブ上部に「今日の復習」カード**: 復習対象件数バッジ + 開始ボタン。対象 0 件なら「今日の復習は完了 🎉」表示。
- **ReviewSessionView（新規）**: 1問ずつ出題 → 回答 → 正誤フィードバック（正解時に例文・イラスト・TTS 再生ボタンを表示して強化）→ 次へ。セッション内で不正解だった単語は最後にもう一度出題。上限は1セッション 20 問（超過分は続けて次セッション可）。
- **WordDetailView に復習状態表示**: 次回復習日・ステップ・正答率を表示。
- 通知（「今日の復習があります」ローカル通知）は将来検討、スコープ外。

## 4. 影響範囲

- iOS のみ（v1）: `Models/Word.swift`（WordReviewState 拡張）、`Views/WordsView.swift`（復習カード追加）、新規 `Views/ReviewSessionView.swift`、新規 `Support/ReviewScheduler.swift`、新規 `Support/FormatSelector.swift`（比率調整付き形式選定）、`Views/WordDetailView.swift`（状態表示）。
- backend / 管理画面: 変更なし（v2 の AI 問題生成時に `index.ts` / `wordInfo.ts` パターンで追加予定）。
- docs: `docs/specs/data-model.md` §5/§10 更新、`docs/specs/app-spec.md` §3.2 の保留事項解消を追記。

## 5. テスト方針

- `ReviewScheduler` を純関数として実装し、ユニットテストで検証: 正解時のステップ進行と dueDate、不正解時のリセット、最終ステップ維持、日付境界（深夜・タイムゾーン）。
- 4択の選択肢生成: 誤答が正答と重複しない・登録語 4 件未満時のフォールバック・イラスト4択のイラスト不足時フォールバックをユニットテスト。
- 品詞・活用形ラベルの日→英マッピング: 既知ラベルの変換と、未知ラベル時に該当形式（TC7・TC8・TT3・VC7）が出題対象から外れることをユニットテスト。
- テキスト入力（TT / IT / VTT / VT 系）の判定: 正規化（大文字小文字・前後空白・句読点）と VT2 の一致率判定をユニットテスト。
- `FormatSelector`: 素材が十分な場合にセッション内の実績比率が目標比率（出題 50:50、回答 60:30:10）へ収束すること、素材不足時に出題可能な形式へフォールバックし例外を出さないことをユニットテスト。
- UI はシミュレータで手動確認: 復習対象の抽出（dueDate 条件の `@Query`／フィルタ）、セッション完走、reviewState の永続化、既存単語（reviewState 既定値）の後方互換。

## 6. Phase 分割

- Phase 1: 設計確定・スペック更新（本プラン + `data-model.md` の WordReviewState/Question 位置づけ更新 + `app-spec.md` §3.2 の保留事項解消）
- Phase 2: `ReviewScheduler`・`FormatSelector`（比率調整） + `WordReviewState` 拡張 + ユニットテスト
- Phase 3: ReviewSessionView（確定した出題形式）と Words タブの「今日の復習」導線
- Phase 4: WordDetailView への復習状態表示・仕上げ（動作確認、DONE 移動・プランのアーカイブ。
  アーカイブ時に `docs/specs/data-model.md`・`docs/specs/app-spec.md` から本プランへのリンクを
  `docs/plans/archive/` のパスへ更新する）

## 6.5 Phase 3 再開用メモ（セッション復帰時にここから読む）

### 進捗

- **Phase 1 完了**（commit `357f5e6`）: data-model.md §5 確定・Question 位置づけ注記・app-spec.md §3.2 解消
- **Phase 2 完了**（commit `f8c7f06`）: 以下を実装済み・ユニットテスト全46件成功
- **Phase 3 が次**: ReviewSessionView + Words タブ「今日の復習」導線 + タブバッジ

### Phase 2 で実装済みの部品（そのまま使う）

- `Models/Word.swift`: `WordReviewState` に `stepIndex` / `correctCount` / `lapseCount` 追加済み（旧データはデコードでデフォルト0）
- `Support/ReviewScheduler.swift`:
  - `ReviewScheduler.reviewed(_:isCorrect:at:calendar:) -> WordReviewState`（純関数。正解=現在ステップの間隔を適用しステップ+1、不正解=step 0・+3日）
  - `ReviewScheduler.isDue(_:on:calendar:) -> Bool`（ローカル日付で dueDate <= 今日）
- `Support/FormatSelector.swift`:
  - `ReviewQuestionFormat`（28形式 enum、`promptBucket`/`answerBucket` 付き）
  - `FormatSelector.availableFormats(for: ReviewWordMaterial) -> Set<ReviewQuestionFormat>`
  - `FormatSelector.select(availableFormats:sessionCounts:targets:using:) -> ReviewQuestionFormat?`（targets 省略時 `.v1`。RNG 注入可）
  - `ReviewWordMaterial(text:aiInfo:hasIllustration:distractors:)` / `ReviewDistractorPool(wordCount:definitionCount:exampleCount:illustrationCount:)`
- `Support/GrammarLabelMapping.swift`: `englishPartOfSpeech(for:)` / `englishInflectionForm(for:)` / `posChoices`

### Phase 3 でやること

1. **問題組み立ての純関数**（新規 `Support/ReviewQuestionBuilder.swift` 推奨）: 形式ごとの問題文・正答・誤答選択肢の生成、テキスト入力の正規化判定（大文字小文字・前後空白・句読点）、VT2 の単語単位一致率判定。§5 テスト方針の残り（選択肢の重複なし・フォールバック・入力判定）をユニットテストで
2. **ReviewSessionView（新規）**: 1問ずつ出題→回答→フィードバック（正解時に例文・イラスト・TTS 再生）→次へ。上限20問、セッション内の不正解単語は最後に再出題。**reviewState への反映は各単語の初回解答のみ**（再出題は表示のみ、`ReviewScheduler.reviewed` を二重適用しない）
3. **WordsView に「今日の復習」カード**: List 上部に件数+開始ボタン、対象0件なら「今日の復習は完了 🎉」
4. **Words タブにバッジ**: `ContentView.swift` の `WordsView().tabItem{...}` に `.badge(dueCount)`。ContentView に `@Query` を足して `ReviewScheduler.isDue` でフィルタ

### 統合ポイント（調査済みの実装パターン）

- **復習対象の抽出**: `reviewState` は SwiftData の埋め込み Codable のため `#Predicate` でのネスト条件は避け、`@Query` で全 `Word` を取り `ReviewScheduler.isDue($0.reviewState)` でメモリ内フィルタする（件数は小さい）
- **targetLanguage の解決**（WordDetailView:209 のパターン）: `word.aiInfoLanguage ?? UserDefaults.standard.string(forKey: AppSettingsKeys.targetLanguageCode) ?? AppSettingsKeys.defaultTargetLanguageCode`
- **イラスト有無/表示**: `WordIllustrationStore.localURL(word: word.text, targetLanguage: lang) != nil`（senseIndex 省略=0）。表示は `AsyncImage(url:)` ではなく `UIImage(contentsOfFile:)` 等ローカル読み込み（WordDetailView の `WordIllustrationRow` 参照）
- **TTS 再生**（WordDetailView の `TTSButton` パターン）:
  - voice/model は `@AppStorage(AppSettingsKeys.ttsVoice/.ttsModel)`。model が `"local"` ならサーバ送信時 `AppSettingsKeys.fallbackServerTTSModel`（"flash"）に読み替え
  - 生成済み確認: `TTSAudioStore.localURL(text:voice:model:)` → あれば `TTSPlaybackService.play(url:)`
  - 未生成: `BackendAPI.post(path: "api/tts", body: {text, voice, model})` → `TTSAudioStore.save(...)`。音声問題では生成待ちを避けるため、**未生成時は `SpeechService.speak(_:languageCode:)`（AVSpeechSynthesizer）へフォールバック**するのが簡単
- **UI テスト**が `accessibilityIdentifier` を参照する慣習（例: `wordAddButton`）。新規ボタンにも識別子を付ける

### ビルド・テストコマンド

```bash
cd ios && xcodegen generate   # 新規ファイル追加後に必須
xcodebuild test -project ESLLearningAssistant.xcodeproj -scheme ESLLearningAssistant \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:ESLLearningAssistantTests
```

## 7. 調査: 音声入力を使った問題作成はどのようにできるか（AI 音声認識を含む）

TODO の調査項目「音声入力を使った問題作成がどのようにできるか調査をする」への回答（調査日: 2026-07-03）。

### 結論（要約）

**技術的に十分可能。ただし「何を判定したいか」で使う技術が変わる。**

1. **「正しい単語を発話できたか」の判定（想起テスト）** → iOS 標準のオンデバイス音声認識（`SFSpeechRecognizer`、iOS 17 対応）で**無料・端末完結**で実装できる。これが最初の一歩として推奨。
2. **「発音の質」の採点（発音テスト）** → 汎用の音声認識では原理的にできない（ASR は訛った発音を「正しい単語」に正規化して解釈するため）。専用の **Azure Speech Pronunciation Assessment** が本命（音素レベルのスコア、従量課金も軽微）。
3. **マルチモーダル LLM（Gemini / GPT-4o）に音声を直接渡して発音採点させる**方式は、研究では可能性が示されているが精度が不安定で、専用 API に劣る。ただし「採点結果を踏まえた日本語フィードバック文の生成」には LLM が最適（音声ではなくスコアをテキストで渡す）。

### 7.1 音声入力の出題形式（TV1〜TV8・IV1・VV1・VTV1、全11形式を候補として採用）

形式 ID の表記ルールは §3.3 と共通（TV = 出題テキスト・回答音声入力、IV = 出題イラスト・回答音声入力、VV = 出題音声・回答音声入力、VTV = 出題音声+テキスト・回答音声入力）。判定技術の軽い順（オンデバイス ASR → 発音評価 API → STT + LLM）に3グループ。実装時にこの中から選定する。

**グループ1: オンデバイス ASR + 文字列照合で判定（無料、Step 1 向き）**

| # | 形式 | 出題 → 回答 | 評価 | 必要データ |
| --- | --- | --- | --- | --- |
| TV1 | 定義→単語発話 | 英語定義を表示（or 音声再生）→ 単語を発話（TC1/VC3 の発話版） | 一致 | englishDefinition |
| TV2 | 例文穴埋め発話 | 対象語を空所にした例文を表示 → 入る単語を発話（TC3 の発話版） | 一致 | examples |
| TV3 | 活用形発話 | "Say the past tense of *go*" → "went" と発話 | 一致 | inflections |
| TV4 | コロケーション完成発話 | "make a ___" を表示 → 空所の語を発話 | 一致 | collocations |
| TV5 | 例文音読（カラオケ判定） | 例文を表示 → 音読。認識の部分結果で単語を順に色付けし、一致率で正誤判定 | 一致率 | examples |
| IV1 | イラスト→単語発話 | 生成済みの単語イラストだけを表示 → 単語を発話。「見て・言う」の直結で想起強度が高い | 一致 | 単語イラスト（生成済み） |
| VV1 | リッスン&リピート | 例文 TTS を再生（**文は非表示**）→ 聞いた文をそのまま復唱 → 一致率判定。リスニング+スピーキング複合（シャドーイング） | 一致率 | examples + TTS（既存基盤） |
| VTV1 | 例文シャドーイング | 例文 TTS を再生し**文も表示** → 見ながら復唱 → 一致率判定。VV1（文非表示）の低負荷版で、TV5（音読）との中間 | 一致率 | examples + TTS（既存基盤） |

- グループ1（TV1〜TV5・IV1・VV1・VTV1）は判定が「正規化 + 単語一致 / diff」の純関数で済み、v1 の設計方針（正誤が客観的・ユニットテスト可能）にそのまま収まる。
- TV5/VV1 の一致判定は完全一致・部分一致とも可能: 正規化（小文字化・句読点除去）後に単語単位の diff（編集距離/LCS）を取り、一致率としきい値で正誤判定。`SFSpeechRecognizer` の部分結果でリアルタイムに読めた単語を色付けできる。正規化ルール（"don't" vs "do not"、数字表記等）の作り込みが必要。
- VV1 は VC6（例文聞き分け）の上位互換的な高負荷形式。ASR の1分制限内に収まる短い例文に限定する。

**グループ2: 発音評価 API（Azure Pronunciation Assessment）で判定（Step 2 向き）**

| # | 形式 | 出題 → 回答 | 評価 | 備考 |
| --- | --- | --- | --- | --- |
| TV6 | 単語発音チェック | 単語と IPA を表示 → 発音し、音素レベルでスコア（80点以上で正解など） | 発音スコア | IPA 表示は答え合わせ画面に回す手も |
| TV7 | ミニマルペア発音 | "Say **ship** (not sheep)" のように紛らわしいペアの一方を発音させ、正しく言い分けられたかを音素スコアで判定 | 発音スコア | 日本人学習者の弱点（L/R 等）に直撃。ただしミニマルペア辞書の用意が必要で実装コストは一段高い |

- Azure の scripted モードは参照テキストとの単語単位の照合（omission / insertion / mispronunciation）と completeness（部分一致率）が組み込みで返るため、音読系の部分一致判定を自前実装する必要もなくなる。

**グループ3: STT + LLM 判定（自由回答、Step 3 向き）**

| # | 形式 | 出題 → 回答 | 評価 | 備考 |
| --- | --- | --- | --- | --- |
| TV8 | 単語を使って文を作る | "Make a sentence using *reluctant*" → 自由に発話 → 文字起こしを Claude（`callStructured`）に渡し「文法的に成立し、単語を正しい意味で使えているか」を JSON 判定 | LLM 判定 | 最も能動的な想起。判定の甘辛はプロンプトで調整 |

**マトリクスの空きマス**: モダリティ組み合わせとしての空きマス（TT・IC・IT・VTT・イラスト4択回答）は §3.3 の v1 採用形式に昇格済み（TT1〜TT3・IC1・IT1・VTT1・TC11・VC8）。残る未採用は素材軸の拡張アイデア: 類義語・対義語・コロケーション・品詞の音声出題版（VC 系の拡張）、スペリングビー形式（単語音声→綴りを1文字ずつ発話）など。

### 7.2 技術選択肢の比較

**A. オンデバイス音声認識（無料）**

- `SFSpeechRecognizer`（iOS 10+、本アプリの deployment target iOS 17 で利用可）: オンデバイス認識対応。`contextualStrings` に単語帳の語彙（〜100 語程度）を渡すと該当語の認識精度をブーストできるため、「単語帳の単語を言い当てる」用途と相性が良い。1 セッション 1 分制限があるが単語回答には十分。
- `SpeechAnalyzer` / `SpeechTranscriber`（iOS 26+）: 新 API。完全オンデバイスで Whisper Large V3 Turbo 比 2 倍高速とされるが、**iOS 26 専用**かつ `contextualStrings` 相当のカスタム語彙機能が未提供。deployment target が iOS 17 の現状では、当面 `SFSpeechRecognizer` を使い、将来バージョン分岐で移行するのが現実的。
- 制約: ASR は非ネイティブ訛りを「正しい単語」に正規化して解釈しがち。つまり**多少発音が悪くても正解になる**。想起テスト（覚えているか）用途ではむしろ寛容で好都合だが、発音評価はできない。同音異義語（flour/flower 等）は綴りで区別できないため、判定時に同音語も正解扱いにするか、該当語では TV1/TV2 を出題しない。

**B. クラウド AI 音声認識（STT）**

| サービス | 料金 | 備考 |
| --- | --- | --- |
| OpenAI `gpt-4o-transcribe` | $0.006/分 | Whisper 比で WER 改善。OPENAI_API_KEY は既に backend にある |
| OpenAI `gpt-4o-mini-transcribe` | $0.003/分 | 半額。単語回答判定には十分 |
| Gemini 音声入力（2.5 Flash） | 音声は 32 tokens/秒 ≒ $0.002/分 | GEMINI_API_KEY 既存。STT 専用 API ではなく汎用マルチモーダル入力 |

- オンデバイスより認識精度は高いが、「発音を正規化する」性質は同じで発音評価には使えない。録音アップロードのレイテンシ（1〜3 秒）が毎問かかる点がクイズ UX 上の難点。**発話回答型（TV1〜TV4・IV1 等）ならオンデバイスで足り、クラウド STT を使う積極的理由は薄い**。TV8（自由回答）では文字起こし→LLM 判定の前段として有用。

**C. マルチモーダル LLM に音声を渡して発音採点**

- GPT-4o / Gemini は音声を直接入力でき、研究（TextPA 2025、AudioJudge 2025 等）ではゼロショット発音採点の可能性が示されているが、**専用システムに比べ精度が不安定で、厳密な採点には不足**というのが 2026 年時点の評価。
- 有効な使い方は「音声を渡す」のではなく「**発音評価 API の音素スコアをテキストで渡し、日本語のアドバイス文を生成させる**」構成。これなら既存の `callStructured`（Claude）パターンをそのまま流用でき、安定・安価。

**D. 発音評価専用 API（TV6/TV7 の本命）**

| サービス | 料金 | 特徴 |
| --- | --- | --- |
| Azure Speech Pronunciation Assessment | STT $1/時 + 評価 $0.30/時（≒ $0.022/分） | 音素・単語・文レベルの accuracy / fluency / completeness スコア。33 ロケール。iOS 用 Speech SDK あり。個人開発で従量課金のみで使える |
| SpeechAce | 非公開（要問い合わせ） | 音素・音節レベル。IELTS/TOEFL 相関スコア。教育事業者向け |
| ELSA API | 非公開（要問い合わせ） | 非ネイティブ訛りデータ 2000 万人分。B2B 契約前提 |

- 個人開発で現実的なのは Azure 一択。iOS SDK でストリーミング評価でき、キー秘匿は「backend が Azure の短期トークンを発行して iOS に渡す」標準パターンで対応（新プロバイダ追加になるので `config.ts` / 管理画面の料金ページへの追加が必要）。

### 7.3 コスト概算（1 セッション 20 問・全問音声入力・1 回答 5 秒発話と仮定）

- オンデバイス ASR: **$0**
- gpt-4o-mini-transcribe: 約 $0.005/セッション
- Gemini 2.5 Flash 音声入力: 約 $0.003/セッション
- Azure Pronunciation Assessment: 約 $0.036/セッション

いずれも既存の TTS 生成コストと同水準以下で、コストは選定の決め手にならない。決め手は**判定できる内容（想起 vs 発音）とレイテンシ・実装量**。

### 7.4 実装上の前提・課題（共通）

- 現状アプリにはマイク入力・音声認識のコードは一切ない（音声は再生のみ）。`NSMicrophoneUsageDescription` と `NSSpeechRecognitionUsageDescription` の追加、`AVAudioEngine` での録音、`AVAudioSession` カテゴリの再生⇄録音切り替え（既存 `TTSPlaybackService` との共存）が新規実装になる。
- 録音 UX: 発話開始/終了の検知（ボタン押下中録音 or 無音検知）、騒がしい環境でのフォールバック（同じ問題をタップ回答に切り替えられる導線）が必要。
- 判定の寛容さ: 大文字小文字・前後空白の正規化、活用形（answered → answer）を正解にするか、同音異義語の扱いをルール化する。

### 7.5 推奨ロードマップ

1. **Step 1（v1.x、無料）**: グループ1（TV1〜TV5・IV1・VV1・VTV1）から数形式を `SFSpeechRecognizer`（オンデバイス + `contextualStrings`）で追加。backend 変更なし・追加コストなし。まず「話して答える」体験を検証する。
2. **Step 2（v2）**: グループ2（TV6/TV7）を Azure Pronunciation Assessment で追加。backend にトークン発行エンドポイントと料金ページ対応を追加。
3. **Step 3（v2+）**: Azure の音素スコアを Claude（`callStructured`）に渡して日本語の発音アドバイス生成。TV8（自由回答）はクラウド STT + LLM 判定で追加。

参考: [Apple Speech framework](https://developer.apple.com/documentation/speech/) / [SpeechAnalyzer vs SFSpeechRecognizer](https://blakecrosley.com/blog/speech-framework-vs-sfspeechrecognizer) / [iOS Speech Recognition in 2026 (Picovoice)](https://picovoice.ai/blog/ios-speech-recognition/) / [Azure Pronunciation Assessment](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/how-to-pronunciation-assessment) / [Azure Speech 料金](https://azure.microsoft.com/en-us/pricing/details/speech/) / [OpenAI STT 料金](https://costgoat.com/pricing/openai-transcription) / [Gemini API 料金](https://costgoat.com/pricing/gemini-api) / [SpeechAce API](https://www.speechace.com/api-plans/) / [ELSA API](https://elsaspeak.com/en/elsa-api/) / [LMM を発音評価に使う研究 (2025)](https://arxiv.org/html/2503.11229v1) / [TextPA: LLM ゼロショット発音評価 (2025)](https://arxiv.org/html/2509.14187)
