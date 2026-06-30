# データ構造資料の作成プラン

## 目的・背景

[docs/specs/app-spec.md](../specs/app-spec.md) 9章「未確定事項」に挙げた
「データモデルの詳細スキーマ（Lesson / Photo / Word / Question / QuizResult 等）」を確定し、
Phase 1〜3 の実装（[ios-app-skeleton](archive/ios-app-skeleton.md) で作成したスケルトンへの実装）に
着手できる状態にする。本タスクはドキュメント作成のみで、コード実装は対象外。

## 対応方針

- 仕様書 3〜4章（撮影・単語帳・問題作成・データ管理単位）を元に、以下のエンティティを設計する
  - `Lesson`（授業単位）, `Photo`（撮影画像＋OCR・翻訳）, `Word`（単語帳）,
    `Question`（生成された問題）, `QuizResult`（演習結果）
  - 上記から参照される補助 enum（処理ステータス・問題形式 等）
- 永続化方式は iOS 17 / SwiftData を前提とする（`ios/project.yml` の deploymentTarget が iOS 17 のため）
- 画像本体はファイルシステム（Documents配下）に保存し、モデルにはファイル名のみ持たせる方針とする
  （DB に Data blob を持たせない）
- レッスン単位ビュー／全体一覧ビュー（仕様書4章）の両方から参照できるリレーションにする
- 単語帳の間隔反復アルゴリズムの詳細・対応言語リストは本タスクのスコープ外
  （仕様書9章に残課題として明記したまま残す）
- 成果物は `docs/specs/data-model.md` に新規作成し、`app-spec.md` 9章から参照を追加する

## 影響範囲

- 新規: `docs/specs/data-model.md`
- 変更: `docs/specs/app-spec.md`（9章に参照リンクを追記）
- 変更: `TODO.md` / `DONE.md`（タスク移動）
- コード変更なし（Swift モデルの実装は別タスク・別 Phase で行う）

## テスト方針

- ドキュメントタスクのためテストコードはなし
- 仕様書 3〜4章の要件（OCR・翻訳・単語情報・問題形式・演習結果・レッスン/全体ビュー）が
  スキーマ上で漏れなく表現できているかをセルフレビューする
