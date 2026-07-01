# OCR結果（英語）のTTS読み上げ機能

## 目的・背景

`PhotoDetailView`（`ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`）では
撮影した写真のOCR結果（英語, `photo.ocrText`）と翻訳結果（日本語, `photo.translatedText`）を
Markdown整形して表示している（40-50行目）が、音声での読み上げ機能は無い。

英語学習者がネイティブの発音を確認できるよう、OCRで文字起こしされた英語文をTTSで
読み上げるボタンを追加する。

なお `docs/specs/app-spec.md` / `docs/specs/screen-design.md` に記載のあるTTSは
単語帳（Vocabulary、Phase 2で実装予定）の単語単位の発音再生であり、本タスクとは別軸。
本タスクはOCR結果全文（英語）の読み上げのみを対象とし、翻訳（日本語）文は対象外とする。

現状 iOS・backend いずれにも音声再生関連コード（AVFoundation等）は存在せず、新規実装となる。
`AVSpeechSynthesizer`はデバイス内で完結し追加のAPI通信・コストが発生しないため、
バックエンドにTTS用APIを追加せずiOSローカルのみで実装する。

## 対応方針

### Step 1: SpeechServiceの新設
- `ios/ESLLearningAssistant/Sources/Services/SpeechService.swift` を新規作成
- `AVSpeechSynthesizer`をラップした`ObservableObject`
  - `@Published private(set) var isSpeaking: Bool`
  - `func speak(_ text: String, languageCode: String = "en-US")`
    - 空文字列は無視
    - 発話前に`AVAudioSession`のcategoryを`.playback`に設定・activateする
      （サイレントスイッチON時でも再生されるようにするため）
    - 既に発話中なら一旦stopしてから新しい発話を開始する
  - `func stop()`
  - `AVSpeechSynthesizerDelegate`に準拠し、発話終了/キャンセル時に`isSpeaking`を`false`に戻す

### Step 2: PhotoDetailViewへの再生ボタン追加
- `@StateObject private var speechService = SpeechService()` を追加
- 「OCR結果（英語）」セクション（41-44行目）のヘッダー行に再生/停止トグルボタンを追加
  - `photo.ocrText`が空/nilなら非表示 or disabled
  - Markdown記号（`#`, `**`等）を読み上げないよう、`markdownText`と同様に
    `AttributedString(markdown:)`でパースしてから`String(attributed.characters)`で
    プレーンテキストを取り出し、それを`speak`に渡す
  - ボタンのアイコンは`isSpeaking`に応じて`speaker.wave.2` / `stop.fill`を切り替え
- 翻訳（日本語）セクションには追加しない
- `.onDisappear`および`photo.id`が変わる`.task(id:)`のタイミングで`speechService.stop()`を呼び、
  画面遷移時に発話が続かないようにする

## 影響範囲

- 新規ファイル: `ios/ESLLearningAssistant/Sources/Services/SpeechService.swift`
- 変更ファイル: `ios/ESLLearningAssistant/Sources/Views/PhotoDetailView.swift`
- SwiftDataモデル（`Photo.swift`等）の変更なし
- backend側の変更なし

## テスト方針

- シミュレータ/実機のGUI操作権限がこのセッションでは無いため、実際の音声再生確認は
  ユーザー側での確認を依頼する
- `xcodebuild`でのビルド確認（コンパイルエラーが無いこと）を実施する
- 可能であれば `run-ios-device.sh` での実機ビルドまで確認する
