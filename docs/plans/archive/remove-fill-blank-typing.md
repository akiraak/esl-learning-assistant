# 穴埋めテキスト入力形式（tt2・vtt1）の廃止

## 目的・背景

例文の空所を自由入力で答えさせる形式は、空所に入り得る語の候補が多すぎて
「何を書けば良いのか分からない」ため出題をやめる。対象は次の2形式:

- `tt2`: 例文穴埋め入力（tc3 の入力版）
- `vtt1`: 例文リスニング穴埋め入力（vtc1 の入力版）

穴埋めでも4択（tc3・tc6・vtc1）は選択肢が答えを絞るため存続。
定義→単語入力（tt1）・活用形入力（tt3）・ディクテーション（vt1・vt2）も
答えが一意に定まるため存続する。

## 対応方針

- backend: `AI_FORMAT_SPECS` から tt2・vtt1 を削除（新規生成を停止）
- backend: 起動時マイグレーションで保存済みの tt2・vtt1 行を削除
  （`DELETE FROM quiz_questions WHERE format IN ('tt2','vtt1')`。冪等）
- iOS: `ReviewQuestionFormat` から `.tt2`・`.vtt1` を削除
  （bucket 判定の switch も更新）。サーバに旧行が残っていても、
  RemoteQuizQuestionService は要素単位デコード（LenientQuestion）のため
  未知形式は1件単位で自然に捨てられる

## 影響範囲

- backend: `src/quizQuestions.ts`（形式定義）、`src/db.ts`（クリーンアップ）
- iOS: `Support/FormatSelector.swift`（enum とコメントの形式数 28→26）
- 既存テストは形式を列挙していないため影響なし（全形式は allCases 経由）

## テスト方針

- backend `npm run build` / iOS ユニットテスト全パス
- ローカルサーバ再起動で quiz_questions から tt2・vtt1 行が消えることを確認
- 単語を再生成して tt2・vtt1 が生成されないことを管理画面で確認
