# 管理画面ヘッダーにアプリのアイコンを出す

## 目的・背景

管理画面のサイドバー見出しは「ESL Assistant / ADMIN CONSOLE」の文字だけで、
ブラウザタブにもアイコンが無く、他のタブに紛れると見つけにくい。
iOS アプリのアイコン（`ios/.../AppIcon.appiconset/AppIcon-1024.png`）を縮小して
管理画面のヘッダーと favicon に使い、見分けが付くようにする。

## 対応方針

- `backend/assets/admin-icon.png` を追加する
  - iOS の 1024px アイコンを 128px へ縮小したもの（サイドバー表示 28px・favicon の両用）
  - 置き場所は `__dirname/..` 基準で ts-node 実行（`src/`）でもビルド実行（`dist/`）でも同じ
    `backend/assets` を指す（`config.dataDir` と同じ考え方）
- `GET /admin/icon.png` でこのファイルを返す（内容は不変なので長めの `Cache-Control`）
- `renderPage()` のサイドバー見出しにアイコンを置き、`<head>` に `<link rel="icon">` を足す
- 執筆画面（`compositionView.ts`）にも favicon を足す。URL は他の導線と同じくプロパティ
  （`iconHref`）で受け取り、表示層がパスを持たない今の作りを崩さない

## 影響範囲

- `backend/assets/admin-icon.png`（新規）
- `backend/src/admin.ts`（アイコン配信ルート・ヘッダー・favicon）
- `backend/src/compositionView.ts` と `backend/test/compositionView.test.ts`（`iconHref` の追加）

## テスト方針

- `compositionView.test.ts`: 執筆画面 HTML に favicon の link が入ることを確認
- `npm test` を通す
- `run-server.sh` で起動し、`/admin` のヘッダー表示と `/admin/icon.png` の応答を目視・curl で確認
