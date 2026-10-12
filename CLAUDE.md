## 開発管理画面

タスク・プラン・ファイルの閲覧と編集、Claude Code への依頼は project-manager（`http://127.0.0.1:8200`、`~/project-manager`）で行う。vibeboard は 2026-10 に撤去した。

## タスク管理ルール

- タスクは `TODO.md` で管理する
- タスクが完了したら `TODO.md` から該当項目を削除し、`DONE.md` に移動する
- `DONE.md` には完了日を `YYYY-MM-DD` 形式で付けて記録する
- 新しいタスクが発生したら `TODO.md` の適切なセクションに追加する
- タスクの実施前に `TODO.md` を確認し、優先度の高いものから着手する
- コミット時に `TODO.md` を確認し、実装した機能に対応するタスクがあれば `DONE.md` に移動する

## 作業着手ルール

作業（実装・調査いずれも）を始めるときは、コードに手を入れる前に以下を行う。

1. **プランファイルを作成する**: `docs/plans/<task-name>.md` に実装プラン or 調査プランを作成する
   - 目的・背景、対応方針、影響範囲、テスト方針を最低限記載する
   - 複数 Phase / Step に分かれる場合はファイル内でも Phase / Step を明示する
2. **`TODO.md` に該当項目があるか確認する**
   - 無ければ適切なセクションに追加する
   - 既存項目があれば、その項目に作成したプランファイルへのリンクを追記する（例: `[plan](docs/plans/<task-name>.md)`）
3. **複数 Phase / Step がある場合は `TODO.md` に子タスクとして追加する**
   - 親項目の下にインデントしたチェックボックスで Phase / Step を列挙する
   - Phase / Step が完了するごとにチェックを入れ、全完了で親項目を `DONE.md` に移す
4. **作業完了時の後片付け**
   - 親タスクを `DONE.md` に移動する
   - 対応するプランファイルは `docs/plans/archive/` に移動する

## デプロイ

本番（g3plus サーバ、https://esl.chobi.me/）へのデプロイを依頼されたら、
**まず [`../g3plus-ops/CLAUDE.md`](../g3plus-ops/CLAUDE.md) の「デプロイ共通規約」を読む**。
このリポジトリ側にはデプロイ設定（`docker-compose.yml` / `Dockerfile` / `.env`）を置いていない。

- このサービス個別の手順書: [`../g3plus-ops/docs/workflows/esl-learning-assistant.md`](../g3plus-ops/docs/workflows/esl-learning-assistant.md)
  （通常フローは **DB バックアップ → サーバで `git pull` → build → `up -d` → ログ確認**）
- サーバはこのリポジトリの GitHub `main` から `git pull` するので、**デプロイ前に push しておく**
- デプロイ設定の正本は開発機の `/home/ubuntu/g3plus-ops/esl-learning-assistant/`。
  変更したら scp で転送する（サーバ上の同名ディレクトリを直接編集しない）
- `db.sqlite` には作文（`compositions` 系）＝再生成できないユーザーデータが入る。
  更新前のバックアップは `cp` ではなく手順書の `.backup` を使う（WAL の取りこぼしを防ぐため）
