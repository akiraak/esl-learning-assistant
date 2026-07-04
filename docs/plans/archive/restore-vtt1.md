# vtt1（例文リスニング穴埋め入力）の復活

## 目的・背景

remove-fill-blank-typing.md で tt2 と一緒に vtt1 も廃止したが、vtt1 は
audioText に完全な英文（単語の発音を含む）を読み上げる形式で、聞き取れれば
答えを一意に特定できる。「空所の候補が多すぎる」という tt2 の廃止理由は
当てはまらないため復活させる。tt2 は廃止のまま。

## 対応方針

- backend: `AI_FORMAT_SPECS` に vtt1 を再追加（廃止前と同じ仕様）
- backend: 起動時クリーンアップの対象を tt2 のみに戻す
- iOS: `ReviewQuestionFormat` に `.vtt1` を再追加（bucket 判定も復元）
- 既存単語の保存済み問題には vtt1 が無い（クリーンアップで削除済み）ため、
  保存済み全単語のクイズを管理画面の regenerate 経路で再生成する

## 影響範囲

- backend: `src/quizQuestions.ts`、`src/db.ts`
- iOS: `Support/FormatSelector.swift`
- データ: 保存済み単語のクイズ問題を再生成（音声プリ合成も自動で走る）

## テスト方針

- backend ビルド / iOS ユニットテスト全パス
- サーバ再起動後に全単語を再生成し、vtt1 が保存されることを DB で確認
