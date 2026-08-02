# 外部APIで保存した単語・熟語をアプリに反映する

## 目的・背景

外部アプリから API 経由でサーバに単語・熟語を保存しており、管理画面の単語一覧
（`/admin/words`）にも表示されている。しかし iOS アプリの単語一覧には出てこないため、
サーバ側の単語をアプリへ取り込む機能が必要。

### 現状の確認（実データ）

`words` テーブル 16 行のうち、外部保存されたものは文脈付きで入っている（2026-08-01）。

| word | context | quiz | illustration |
| --- | --- | --- | --- |
| `pick up` | "I picked it up at the sta…" | 未生成 | 未生成 |
| `get around to` | "I finally got around to r…" | 未生成 | 未生成 |

つまり **単語情報（`word_info_json`）は既にサーバに揃っている** が、派生物（クイズ問題・イラスト）は
まだ無い、という状態。

### なぜアプリに反映されないか

アプリの単語一覧 `WordsView.swift:6` はローカル SwiftData への
`@Query(sort: \Word.registeredAt, order: .reverse)` で、`Word` 行はアプリ内の `WordRegistrar` でしか
作られない。アプリからサーバへの通信はすべて「ユーザー操作を起点にした POST」で、
**サーバから状態を引く経路が一つも無い**（唯一の GET ポーリングは自分が投げた文書ジョブの完了待ちだけ）。
起動時同期・pull-to-refresh・バックグラウンド更新のいずれも存在しない。

したがって不具合ではなく、**サーバ→アプリの取り込み経路を新規に作る** のが本タスク。

## 対応方針

### サーバ側: 変更不要

同期元には既存の `GET /api/words`（`docs/plans/archive/word-info-reference-api.md`）をそのまま使う。
`targetLanguage` フィルタ・`limit`/`offset` ページング・`X-API-Secret` 認証が揃っており、
熟語（`pick up` 等）もそのまま返る。**外部アプリ側の保存処理も変更不要**（今のまま `words` に
入れ続ければアプリが拾う）。新しい登録用テーブルやエンドポイントは作らない。

### アプリ側: サーバ単語の差分取り込み

```
iOS ──GET /api/words?targetLanguage=ja──▶ サーバの全単語（ページング）
    └─ ローカルに無い & 取り込み済み台帳に無い語だけ
       WordRegistrar.register(text:) でローカル Word 作成 → 単語一覧に出る
```

**取得**: 全件をページングで取得して差分判定する（現在16行、上限500/回なので実質1リクエスト）。
`updatedSince` によるカーソル方式は採らない。管理画面で単語を再生成すると `updated_at` が
更新されるため、カーソル方式だと「アプリで削除した語が再生成のたびに復活する」ため。

**取り込み**: 取得した語を `WordRegistrar.register(text:in:existingWords:lesson: nil)` に渡す。
既存の登録経路をそのまま再利用でき、以下が自動的に効く。

- 大小無視の綴り一致による重複排除（`WordRegistrar.swift:47-49`）。サーバの `word` は小文字正規化
  済みなので、アプリ側に `Apple` があってもサーバの `apple` と重複しない。
- `aiInfoStatus == .none` なら AI 情報生成が起動 → **サーバに生成済みなのでキャッシュヒットで即完了**
  （追加課金なし）。これにより `translation` が第1語義で埋まる（空だと一覧に訳語が出ないため必須）。
- クイズ問題・イラストの連鎖生成も従来どおり走る（コストは後述）。

`lesson: nil` で登録する。`Word` は `Lesson` に従属しない独立エンティティ（`docs/specs/data-model.md` §1）で、
一覧は全 `Word` を無条件に引くため出現記録ゼロでも表示される。既定レッスンは作らない
（`Lesson` は `Class` 必須で、作るなら合成クラスまで要るため）。

**取り込み済み台帳**: 取り込んだ語のキー（`小文字化した word|targetLanguage`）を `UserDefaults`
（`AppSettingsKeys` に追加）へ保存し、次回以降スキップする。これにより **アプリ側で削除した単語が
次の同期で復活しない**。同期用の `@Model` は作らない（`ModelContainer` の型リストと全 `#Preview` の
更新が必要になり、SwiftData のマイグレーション地雷も踏みうるため）。
設定画面に「取り込み済みをリセット」を置き、台帳を消せば全件を取り込み直せる逃げ道を用意する。

**導線**: 起動時（`ContentView.swift:52-55` の `.task { LessonDateBackfill.runIfNeeded(...) }` に並べる）と、
`WordsView` への `.refreshable` 追加による手動同期。失敗時はサイレントに無視し（オフラインでも
一覧表示を妨げない）、台帳は成功した語だけ前進させる。

### 注意: 初回同期の取り込み範囲と派生生成コスト

- **初回はサーバにあってアプリに無い語をすべて取り込む**。現在サーバには 16 語あり、過去の
  お試し語（`apple` / `banana` / `zebra` 等）も含まれる。不要なものはアプリで一度削除すれば、
  台帳により以後復活しない。
- 取り込んだ語はクイズ問題とイラストが未生成なら生成される。実測値は
  **1語あたりクイズ約 $0.02 + イラスト約 $0.006 ≒ $0.027**（既存データの `quiz_questions` /
  `word_illustrations` の cost_usd 実績）。16語なら約 $0.4 だが、将来まとめて数百語を外部保存した
  場合に効いてくるため、**取り込みは並列にせず逐次実行**して一気に走らないようにする。
  （必要なら「クイズ・イラストは初回復習時まで遅延生成」まで踏み込むが、まずは逐次化で様子を見る。）

### 実装上の注意

`BackendAPI.get(path:)` はクエリ文字列を扱えない（`URL.appendingPathComponent` が `?` を
パーセントエンコードしてしまう）。`URLComponents` で `queryItems` を組める形へ小さく拡張する。
先に追加した `GET /api/words` も同じ理由で現状アプリからは呼べないので、ここで併せて解消する。

## 影響範囲

| 対象 | 変更 |
| --- | --- |
| backend | **変更なし**（既存 `GET /api/words` をそのまま使う） |
| iOS `Services/BackendAPI.swift` | `get` にクエリパラメータ対応を追加 |
| iOS `Services/WordSyncService.swift`（新規） | `GET /api/words` のページング取得クライアント |
| iOS `Support/WordSyncImporter.swift`（新規） | 差分判定と取り込み（`WordRegistrar` に委譲）、台帳更新 |
| iOS `Support/AppSettingsKeys.swift` | 取り込み済み台帳のキーを追加 |
| iOS `Views/ContentView.swift` | 起動時同期の呼び出し |
| iOS `Views/WordsView.swift` | `.refreshable` の追加 |
| iOS `Views/SettingsView.swift` | 「取り込み済みをリセット」 |

SwiftData のスキーマ変更なし（`@Model` の追加・変更なし）。DB スキーマ変更なし。

## テスト方針

- **iOS 単体**（`ESLLearningAssistantTests/WordSyncImporterTests.swift` 新規）: in-memory
  `ModelContainer`（既存 `WordRegistrarTests` と同じ組み方）＋ スタブサービスで検証する。
  1. サーバにのみある語が `Word` として作られる
  2. ローカルに同綴り（大小違い含む）があれば重複を作らない
  3. 台帳にある語はスキップする（削除後に復活しない）
  4. 空レスポンス・取得失敗で何も起きず、台帳も前進しない
  5. ページング（`limit` 到達時に次ページを取りに行く）
- **結合（手動）**: `run-server.sh` でローカル起動 → 外部アプリ相当の curl で新しい熟語を保存 →
  シミュレータでアプリ起動 → 単語一覧に出て訳語と AI 情報が埋まることを確認 →
  再起動しても重複しないこと、アプリで削除しても復活しないことを確認。
- iOS ユニットテストが全件グリーンであること（backend は変更なしだが `npm test` も回す）。

## Phase / Step

- [x] Phase 1: iOS `BackendAPI.get` にクエリパラメータ対応を追加する
- [x] Phase 2: iOS 同期サービス（`GET /api/words` ページング取得）と取り込み処理（`WordRegistrar` 経由・逐次実行）、取り込み済み台帳＋単体テスト
- [x] Phase 3: iOS 起動時同期と `WordsView` の pull-to-refresh、設定の「取り込み済みをリセット」
- [x] Phase 4: シミュレータでの結合確認（外部保存→反映、重複なし、削除後に復活しない）
