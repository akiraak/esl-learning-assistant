# 本文タップ登録: タップ語と無関係な正規化提案が出る問題の調査と対策

## 目的・背景

本文タップで「form」を追加しようとしたところ、確認ダイアログに
「『heard』は『hear』の過去形です / Register “Hear” / Keep “heard”」という
タップ語と無関係な提案が表示された（2026-07-11 報告）。

## 調査結果

### 1. ダイアログの「Keep」はサーバが受け取った入力語のエコー

- iOS はタップされたリンクの `w=` パラメータをそのまま `/api/word-normalize` に送り、
  レスポンスの `input`（サーバ側で trim しただけのエコー）を「Keep “…”」に表示する
  （`TappableEnglishText.swift` / `WordNormalizationFlow.swift` / `backend/src/index.ts`）。
  iOS・backend とも途中で語を置き換える経路は無い。
- よって「Keep “heard”」が出た＝**アプリは実際には “heard”（文頭大文字の “Heard”）を
  リクエストしていた**。lemma が “Hear” と大文字なのも、文頭大文字の入力に整合する。
- 発生機序は次のどちらか（両方とも同じ UX 欠陥に帰着）:
  - **誤タップ**: 本文は全単語がリンクなので、隣接語・隣接行に触れると気づかず別語を引く。
  - **遅延ダイアログ**: 正規化は非同期（haiku 呼び出しで数秒）で、待ち中のタップは
    `isNormalizing` ガードで黙って無視される。先行タップ（heard）の結果ダイアログが、
    後から「form」をタップした直後に表示され、form への応答に見える。
- どちらもタップ時に「どの語を処理中か」の表示が一切無いことが根本原因。

### 2. 文脈付き正規化でタップ語と無関係な提案が返るのは実在するバグ（別件・再現済み）

ローカルで `normalizeWord`（claude-haiku-4-5）を直接呼んで再現:

- word=`form`, context=`"I heard that you need to fill out this form."`
  → `status=phrase_part, lemma="fill out"`（reason:「form は句動詞 fill out の**目的語**」）。
  タップ語が表現の構成語でなく目的語なのに phrase_part が誤発動し、
  タップ語と無関係な lemma を提案してしまう。プロンプトの意図
  （分離目的語は lemma から除く）を「目的語でも phrase_part にしてよい」と誤解している。
- この誤結果は `word_context_normalizations` にキャッシュされ、同じタップで再現し続ける。

### 3. 文頭大文字の入力で提案 lemma も大文字になる

入力 “Heard” に対し lemma “Hear” のように、固有名詞でない語の提案が大文字のまま返る。
Register を押すと語彙リストに “Hear” が大文字で登録される（dedup は大小無視だが表示が汚れる）。

## 対応方針

### Phase 1: backend — プロンプト強化＋結果検証フォールバック

1. `wordNormalize.ts` の文脈付きプロンプトに以下を明記:
   - 正規化・訂正の対象はタップされた語のみ。文脈中の他の語を lemma にしない。
   - phrase_part は「タップ語自体が表現見出しの構成語」の場合だけ。
     目的語・主語として隣接しているだけなら通常ルールで判定する。
   - inflected / misspelled / phrase_part の lemma は固有名詞でない限り小文字で返す
     （文頭大文字の入力 “Heard” でも lemma は “hear”）。スキーマ記述にも反映。
2. 結果検証（文脈付き呼び出しのみ）を追加し、違反時は文脈なしで 1 回だけ再正規化して採用:
   - phrase_part: lemma のトークンにタップ語（小文字比較）が含まれること。
   - inflected / misspelled: reason にタップ語（小文字比較）が含まれること
     （プロンプトが reason に入力語の引用を必須化している）。
   - 検証関数は純関数 `isContextNormalizationConsistent` として export し単体テストする。
   - トークン数は 2 回分を合算して返す（コスト記録の整合）。

### Phase 2: iOS — タップ時フィードバックで誤帰属を防ぐ

1. `WordRegistrationModifier.handleTap` で正規化開始時に既存のトーストを使い
   `Checking “<語>”…` を表示（どの語のリクエストかを即時可視化）。
2. 正規化待ち中の追加タップは黙殺せず、処理中の語を同じトーストで再表示する。

## 影響範囲

- backend: `wordNormalize.ts`（プロンプト・検証）、既存ルート/キャッシュ構造は不変。
- iOS: `TappableEnglishText.swift` の `WordRegistrationModifier` のみ。
  `WordAddView`（手動入力）は対象外（入力語をユーザー自身が把握しているため）。

## テスト方針

- backend: `npm run build` / `npm test`。`isContextNormalizationConsistent` の単体テストを追加
  （phrase_part 構成語あり/なし、inflected の reason 引用あり/なし、canonical 素通し）。
- backend: 再現スクリプトで「form + fill out 文脈」が phrase_part 誤発動しない
  （または検証フォールバックで canonical に落ちる）ことを確認。
- iOS: シミュレータビルドが通ること。既存の WordNormalizationFlow / UI テストに影響しないこと。
