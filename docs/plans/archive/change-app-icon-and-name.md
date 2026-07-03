# アイコンとアプリ名の変更

## 目的・背景

- iOS アプリのホーム画面表示名が現状ターゲット名そのままの **"ESLLearningAssistant"** になっており、製品名として表示するには不適切。
- アプリアイコンが未設定（`AppIcon.appiconset/Contents.json` に 1024x1024 のスロットだけあり、**画像ファイルが存在しない**プレースホルダ状態）。
- ユーザーに見せられる名前とアイコンを設定する。

## 現状調査サマリ

| 項目 | 現状 | 定義場所 |
|---|---|---|
| 表示名 | `ESLLearningAssistant`（`CFBundleDisplayName` 未設定、`CFBundleName = $(PRODUCT_NAME)`） | `ios/ESLLearningAssistant/Resources/Info.plist:17-18` |
| PRODUCT_NAME | `$(TARGET_NAME)` = `ESLLearningAssistant` | XcodeGen 生成（`ios/project.yml` が真の定義元） |
| Bundle ID | `com.akiraak.esllearningassistant` | `ios/project.yml:30`、`run-ios-device.sh:9` にもハードコード |
| アイコン | 画像ファイルなし | `ios/ESLLearningAssistant/Resources/Assets.xcassets/AppIcon.appiconset/` |
| ビルドスクリプト | scheme 名 / `${SCHEME}.app` / Bundle ID に依存 | `run-ios-device.sh:7-9,100,105,113` |
| 管理画面の名称 | ブランド表記 `ESL Assistant`、ページタイトル `ESL Learning Assistant` | `backend/src/admin.ts:170,253,331,385,527,563,636,781` |

補足:
- `.xcodeproj` は XcodeGen 生成物。**変更は `ios/project.yml` に対して行い、`xcodegen generate` で再生成する**（pbxproj 直接編集はしない）。
- `project.yml:31` に `ASSETSCATALOG_COMPILER_APPICON_NAME`（S が 1 つ多い typo）がある。正しい綴りの設定も pbxproj に出力されているため実害はないが、ついでに修正する。

## 対応方針

**表示名のみを変更する最小方針**を採る。ターゲット名 / スキーム名 / PRODUCT_NAME / Bundle ID は変更しない。
これにより `.app` ファイル名と Bundle ID が変わらず、`run-ios-device.sh` の修正が不要になる。

### 決定事項（実装着手前に確定する）

- [x] **新しいアプリ表示名**: `ESL Assistant`
- [x] **アイコンのデザイン方針**: 支給画像（緑背景に本・鉛筆・吹き出し・"E" の 3D イラスト、1254x1254 PNG）を 1024x1024 にリサイズして使用
- [x] 管理画面（backend）の名称も合わせて変える → Phase 3 実施（ページタイトル・起動ログ・README を `ESL Assistant` に統一）

### Phase 1: アプリ表示名の変更

1. `ios/project.yml` の `targets.ESLLearningAssistant.info.properties` に `CFBundleDisplayName: <新表示名>` を追加
2. `xcodegen generate` で `.xcodeproj` を再生成
3. 実機/シミュレータでホーム画面の表示名を確認

### Phase 2: アプリアイコンの設定

1. 1024x1024 PNG のアイコン画像を用意（GPT Image 2 生成 or 支給画像。角丸・透過なしのフル正方形）
2. `AppIcon.appiconset/` に PNG を配置し、`Contents.json` の universal スロットに `filename` を追記
3. `ios/project.yml:31` の `ASSETSCATALOG_...` typo を `ASSETCATALOG_COMPILER_APPICON_NAME` に修正し再生成
4. ビルドしてホーム画面のアイコン表示を確認

### Phase 3: 管理画面・README の名称更新（名称統一する場合のみ）

1. `backend/src/admin.ts` のブランド表記（:170）とページタイトル（:253 ほか計 7 箇所）を新名称に更新
2. `backend/src/index.ts:495` の起動ログ文言を更新（任意）
3. `README.md` のタイトル・説明を新名称に合わせて更新
4. backend をビルドし直し（`dist/` は生成物なので `src/` のみ編集）、管理画面の表示を確認

## 影響範囲

- `ios/project.yml`（＋XcodeGen 再生成による `.xcodeproj` の差分）
- `ios/ESLLearningAssistant/Resources/Assets.xcassets/AppIcon.appiconset/`
- `backend/src/admin.ts`、`backend/src/index.ts`、`README.md`（Phase 3 実施時）
- **変更しないもの**: ターゲット名・スキーム名・Bundle ID・`run-ios-device.sh`・Swift コード（`BackendAPI.swift:32` のフォールバック文字列は内部ログ用のためそのまま）

## テスト方針

- `run-ios-device.sh` で従来どおりビルド・インストール・起動できること（スクリプト無修正で通ることが最小方針の検証になる）
- ホーム画面で新しい表示名とアイコンが反映されていること
- Phase 3 実施時は管理画面をブラウザで開き、ヘッダー・各ページタイトルを目視確認
