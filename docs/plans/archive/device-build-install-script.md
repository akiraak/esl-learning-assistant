# 実機ビルド・インストール用シェルスクリプト

## 目的・背景

実機（AkiraのiPhone、無線接続）への動作確認のたびに `xcodebuild` → `.app` パス検索 →
`devicectl device install app` を手打ちしているため、スクリプト化して再実行を容易にする。

## 対応方針

- `ios/run-on-device.sh` を新規作成
- `xcodebuild build` でビルドし、DerivedData 配下の `.app` を検索
- `xcrun devicectl device install app` でインストール
- 成功したら `xcrun devicectl device process launch` で起動まで行う
- デバイスIDは環境変数 `DEVICE_ID` で上書き可能にしつつ、デフォルトは
  「ペアリング済みデバイス一覧から `devicectl list devices` で1台だけ取得」する
  （複数台ある場合はエラーにして手動指定を促す）

## 影響範囲

- `ios/` 配下のみ。既存のXcodeプロジェクト設定（`project.yml` 等）には影響しない。

## テスト方針

- 実際に `./run-on-device.sh` を実行し、ビルド成功・インストール成功・起動まで確認する
- 無線接続が不安定な場合はエラーメッセージで原因（接続切れ等）が分かるようにする
