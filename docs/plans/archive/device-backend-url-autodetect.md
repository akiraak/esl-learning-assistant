# 実機ビルド時にバックエンドURLをMacのIPへ自動設定

## 目的・背景

実機（iPhone）では `AppSettingsKeys.defaultBackendBaseURL`（`http://localhost:8801`）が
iPhone自身を指してしまい、Macで動いているバックエンドに接続できない
（`ios/ESLLearningAssistant/Sources/Support/AppSettingsKeys.swift`）。
これまでは実機ユーザーが毎回アプリの設定画面でMacのIPアドレスを手入力する必要があった。
`run-ios-device.sh` でのビルド・インストール時に自動でMacのLAN IPを既定値として
埋め込むことで、この手動設定を不要にする。

## 対応方針

- Info.plist にビルド設定 `BACKEND_BASE_URL`（Xcodeのビルド設定変数展開 `$(BACKEND_BASE_URL)`）
  を経由して `BackendBaseURL` キーを追加する（`ios/project.yml` で定義、`xcodegen generate` で反映）。
  デフォルト値（通常のXcodeビルド/シミュレータ用）は `http://localhost:8801` のまま。
- `AppSettingsKeys.defaultBackendBaseURL` を、Info.plistの `BackendBaseURL` を読む計算プロパティに変更
  （値が無い/空なら `http://localhost:8801` にフォールバック）。UserDefaultsに既に保存済みの値が
  あればそちらが優先される点は変更しない（`RemoteOCRTranslationService`・`SettingsView` の
  既存ロジックのまま）。
- `run-ios-device.sh` で `ipconfig getifaddr en0/en1/en2` によりMacのLAN IPを自動検出し、
  `xcodebuild ... BACKEND_BASE_URL=http://<IP>:8801 build` として実機向けビルドにのみ注入する。
  `BACKEND_BASE_URL` 環境変数が明示されていればそれを優先する。IP検出に失敗した場合は
  警告を出し `localhost` のままビルドを継続する（従来通り手動設定が必要になる旨を案内）。
- `SettingsView` のフッター文言を、ビルドごとに変わる動的なデフォルト値を案内する形に更新する。

## 影響範囲

- `ios/project.yml`
- `ios/ESLLearningAssistant/Resources/Info.plist`（xcodegen生成物）
- `ios/ESLLearningAssistant/Sources/Support/AppSettingsKeys.swift`
- `ios/ESLLearningAssistant/Sources/Views/SettingsView.swift`
- `run-ios-device.sh`

## テスト方針

- `xcodegen generate` 後、`xcodebuild -scheme ESLLearningAssistant -destination 'generic/platform=iOS Simulator' build` でビルド確認。
- `run-ios-device.sh` は実機接続が無いこのセッションでは実行できないため、
  IP検出・ビルド設定注入のロジックをコードレビューベースで確認する
  （実機での動作確認はユーザー側で実施してもらう）。
