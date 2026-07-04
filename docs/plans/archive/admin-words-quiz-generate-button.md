# 管理画面: 単語一覧にクイズ問題の生成ボタンを追加

## 目的・背景

実機で Today's Review を開くと「Preparing Questions」のまま進まない問題が発生。原因は本番サーバの quiz_questions テーブルが空で、アプリの自己修復トリガ（fire-and-forget）でも生成されていないため。

現状の管理画面では、クイズ問題が0件の単語には生成手段が無い:
- `/admin/quiz-questions` 一覧: 問題がある単語しか並ばない
- `/admin/quiz-questions/item`: 問題0件だと 404
- 再生成 POST `/admin/quiz-questions/regenerate` は存在するが、そこへ到達するボタンが item ページにしかない

単語情報（words テーブル）があれば生成できるので、単語一覧から単語ごとに生成できるようにする。生成失敗時はエラーがブラウザに表示されるため、本番で生成が失敗している原因の診断にも使える。

## 対応方針

1. `/admin/words` 一覧に「クイズ」列を追加
   - `countQuizQuestions(word, target_language)` で問題数を表示
   - 0件: 「生成」ボタン（POST `/admin/quiz-questions/regenerate?word=..&targetLanguage=..`、確認ダイアログ付き）
   - 1件以上: 問題数を `/admin/quiz-questions/item` へのリンクで表示
2. `/admin/words/:id` 詳細ページにも同じ生成ボタン＋問題数を表示（action-buttons に追加）
3. 既存の regenerate ハンドラをそのまま使う（問題0件でも動作する。成功時は item ページへリダイレクト）

## 影響範囲

- `backend/src/admin.ts` のみ（words 一覧・詳細のレンダリング）
- DB 変更なし。iOS 変更なし

## テスト方針

- ローカルで backend を起動し、単語情報あり・クイズ0件の単語で「生成」→ 問題が生成され item ページが表示されること
- 生成済み単語では問題数リンクが表示されること
- 単語情報が無い単語の生成は既存ハンドラの 404 エラーページが出ること
