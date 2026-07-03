# アプリ Settings から SpeechEngine を削除し TTS Model に統合する

## 目的・背景

現在の Settings 画面（Text-to-Speech セクション）には「Speech Engine」（On-Device / Gemini）と
「TTS Model」（Fast / High Quality）の 2 段構えのピッカーがあり、TTS Model は
Speech Engine が Gemini のときだけ有効という従属関係になっている。

これを「TTS Model」ピッカー 1 つに統合し、選択肢に On-Device と Gemini の各モデルを
モデル名の詳細（Gemini 2.5 Flash TTS など）付きで並べることで、設定を分かりやすくする。

- 対応する TODO: `TODO.md` の「アプリSettingからSpeechEngineを削除。TTS Modelだけで選択できるように。Gemini 2.5 TTS などモデル名の詳細を表示する」

## 対応方針

`ttsEngine`（`"local"` / `"gemini"`）キーを廃止し、`ttsModel` キーに統合する。

- `ttsModel` の値: `"local"` / `"flash"` / `"pro"` の 3 択に拡張
  - `"local"`: 端末内蔵 AVSpeechSynthesizer（従来の Speech Engine = On-Device 相当）
  - `"flash"`: Gemini 2.5 Flash TTS（`gemini-2.5-flash-preview-tts`）
  - `"pro"`: Gemini 2.5 Pro TTS（`gemini-2.5-pro-preview-tts`）
- UI ラベル: `On-Device` / `Gemini 2.5 Flash TTS` / `Gemini 2.5 Pro TTS`
- 既定値: `"local"`（従来の defaultTTSEngine = "local" と同じ挙動を維持）
- Voice ピッカーは `ttsModel == "local"` のとき無効化（従来どおり Gemini 選択時のみ有効）
- 単語詳細のサーバ TTS 専用ボタン（WordDetailView の TTSButton）は従来 ttsEngine を無視して
  常にサーバ TTS だったので、`ttsModel == "local"` のときは `"flash"` にフォールバックして送信する
  （旧構成で engine=local のユーザーは ttsModel 既定値 flash で生成していたため、キャッシュキーも一致する）
- 旧 `ttsEngine` キーからの移行: アプリ起動時に UserDefaults を確認し、
  - `ttsEngine == "local"` → `ttsModel = "local"` を設定
  - `ttsEngine == "gemini"` かつ `ttsModel` 未設定 → `ttsModel = "flash"` を設定
  - 移行後は `ttsEngine` キーを削除

## 影響範囲

- `ios/.../Support/AppSettingsKeys.swift`: `ttsEngine` / `defaultTTSEngine` の削除、`defaultTTSModel` を `"local"` に変更、移行処理の追加
- `ios/.../Sources/ESLLearningAssistantApp.swift`: 起動時に移行処理を呼ぶ
- `ios/.../Views/SettingsView.swift`: Speech Engine ピッカー削除、TTS Model ピッカーの選択肢・ラベル変更、footer 文言更新
- `ios/.../Views/PhotoDetailView.swift`: 再生分岐を `ttsEngine == "gemini"` → `ttsModel != "local"` に変更
- `ios/.../Views/WordDetailView.swift`: TTSButton で `"local"` のとき `"flash"` にフォールバック
- バックエンド: 変更なし（`/api/tts` は従来どおり `flash` / `pro` のみ受け取る）

## テスト方針

- iOS アプリのビルドが通ることを確認（xcodebuild）
- Settings 画面に Speech Engine ピッカーが無く、TTS Model が 3 択になっていること
- TTS Model = On-Device で OCR 読み上げが端末内蔵 TTS になること、
  Gemini モデル選択でサーバ TTS になること（コードパス確認）
- 旧 `ttsEngine` の各値からの移行が正しく行われること（ロジック確認）
