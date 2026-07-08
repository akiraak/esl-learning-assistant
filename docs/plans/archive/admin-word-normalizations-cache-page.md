# 管理画面に単語正規化キャッシュ（word_normalizations）の表示・削除を追加

## 目的・背景

入力語の正規化キャッシュ（`word_normalizations`）は、旧プロンプト時代の誤った結果
（例:`writed`→`wrote`）が残ると、デプロイ後もキャッシュ優先で古い値を返し続ける。
現状これを消すには API `regenerate:true` か本番 DB への直接 SQL しか手段がなく、
admin から中身を確認・削除できない。

既に `/admin/word-normalize` はあるが、これは **通信ログ（`word_normalize_requests`）** の
閲覧で、キャッシュ表そのものではない。キャッシュ表 `word_normalizations` を一覧・削除できる
画面を新設する。

## 対応方針

`/admin/words`（`words` キャッシュ表の一覧＋行削除）と同型で実装する。

- **一覧** `/admin/word-normalizations`: 全行を更新日時降順で表示（ID / 入力 / 判定 / lemma /
  理由 / 母語 / モデル / 生成回数 / 作成・更新日時 / 削除ボタン）。判定は既存
  `normalizeStatusBadge` を流用。
- **行削除** `POST /admin/word-normalizations/:id/delete`: 1 行削除して一覧へリダイレクト。
  削除後はアプリからの再リクエストで新プロンプトにより再生成される（自己修復）。
- **全削除** `POST /admin/word-normalizations/delete-all`: 全行削除（confirm 付き）。キャッシュ
  なので安全（要求時に作り直される）。
- ナビに「単語正規化キャッシュ」を追加（既存「単語正規化ログ」の隣）。ログとキャッシュを別項目に。

## 影響範囲

- `backend/src/db.ts` — 追加のみ: `listStoredNormalizations()` / `getStoredNormalizationById()` /
  `deleteStoredNormalization(id)` / `deleteAllStoredNormalizations()`。既存関数は不変。
- `backend/src/admin.ts` — `NavSection` に `word-normalizations` 追加、`NAV_ITEMS` に 1 行、
  GET 一覧 + POST 削除 + POST 全削除、db ヘルパの import 追加。
- iOS・DB スキーマ変更なし。

## テスト方針

- `npm run build`（tsc）が通ること。
- ローカルで `/admin/word-normalizations` が一覧表示され、行削除・全削除が動くこと
  （削除後に該当語を正規化すると再生成されて再びキャッシュに載ること）を curl / ブラウザで確認。
- 既存 `/admin/word-normalize`（ログ）が従来どおり動くこと（無干渉）。
