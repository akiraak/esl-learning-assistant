# 綴り間違いの変化形を原形へ正規化する

## 目的・背景

単語入力の自動正規化（[word-input-normalization](archive/word-input-normalization.md)）で、
`writed` を登録しようとすると「`writed` は `write` の過去形 `wrote` の綴り間違いです。Register wrote」と
提示され、**変化形 `wrote` での登録を勧めてくる**。

本来この機能の目的は入力語を**辞書見出し語（原形）へ正規化**すること。`writed` のように
「綴り間違い」かつ「語形変化」の両方に該当する入力では、綴りを直したうえで**さらに原形 `write` へ
戻して**提示すべき。現状は綴り訂正だけ行って変化形で止まっている。

## 根本原因

`backend/src/wordNormalize.ts` のプロンプト／スキーマが、`inflected`（変化形→原形）と
`misspelled`（綴り訂正）を**独立した別処理**として記述しているため、両方に該当する語で
綴り訂正のみが適用され、原形化されない。`lemma` は「misspelled なら正しい綴り」としか
指示されておらず、「正しい綴りが変化形なら原形へ戻す」まで踏み込んでいない。

## 対応方針

- **lemma は常に辞書の原形（基本形）** という一貫ルールに変更する。
  - 綴りを直した結果が変化形になる場合は、さらに原形へ戻す（例:`writed` → `write`）。
  - `misspelled` の status は「変化形の綴り間違い」も含むと明記する。
- 単純な原形（`recieve`→`receive`）・単純な変化形（`ran`→`run`）の既存挙動は不変。
- reason には原形で登録する旨を含める（母語）。

## 影響範囲

- `backend/src/wordNormalize.ts` — プロンプト＋`lemma`/`status` スキーマ説明の修正のみ。ロジック不変。
- iOS 側は変更不要（`requiresConfirmation` は lemma≠入力なら確認UIを出すため `write` 提示で成立）。
  - ドキュメントコメントの追従のみ: `Sources/Models/WordNormalization.swift` の lemma 説明。
- キャッシュ: `word_normalizations` に `writed` の旧結果（lemma=wrote）が残っていると再現するため、
  テストは `regenerate: true` で行い、必要なら該当行を消す（キャッシュは再生成で自己修復）。

## テスト方針

- curl で `regenerate:true` を付けて確認:
  - `writed` → status=misspelled, lemma=`write`（原形）
  - `ran` → status=inflected, lemma=`run`（回帰なし）
  - `recieve` → status=misspelled, lemma=`receive`（回帰なし）
  - `apple` → status=canonical, lemma=`apple`（回帰なし）
- backend の `tsc` ビルドが通ること。
