# 音声取り込み時の音量ノーマライズ

## 目的・背景

- TODO: 「音声ファイルを読み込むときに音量のノーマライズを行う」
- 授業録音などの取り込み音源は録音環境によって音量がまちまちで、小さすぎる音源は
  端末音量を上げても聞き取りづらい。取り込み時点で音量を揃えれば、再生・シャドーイングの
  体験が安定する。
- 再生側での増幅は不可: `TTSPlaybackService` は `AVAudioPlayer` ベースで、`volume` は
  0〜1.0（減衰のみ）。増幅するには `AVAudioEngine` への全面移行（rate/loop/seek の再実装）が
  必要になり過大。**取り込み時にファイル自体を正規化して保存する方式**を採る。
- 副次効果: 出力を `.aac` に統一すると、現状文字起こし非対応の m4a/mp4
  （`RemoteTranscriptionTranslationService` が送信前に弾く）も取り込み後は対応形式になる。

## 現状

- 取り込み: `AudioFileImporter.importFiles(_:into:context:)`（同期・メインスレッド）が
  選択 URL の Data をそのまま `AudioStorage.save(data:ext:)` で `Documents/Audio/UUID.ext` に保存。
- 呼び出し元は 2 箇所: `AddContentTypeView.handleAudioImport` / `AudioLibraryView.importFiles`。
  どちらも `.fileImporter(allowedContentTypes: [.audio])` なので m4a 含む任意の音声が入ってくる。
- 文字起こし: `RemoteTranscriptionTranslationService` が拡張子で mimeType を決めて送信。
  対応は wav / mp3 / aac / aif(f) / ogg / flac のみ（m4a/mp4 は inline 非対応）、上限 14MB。

## 対応方針

### 正規化アルゴリズム（AudioNormalizer 新規作成）

`ios/ESLLearningAssistant/Sources/Support/AudioNormalizer.swift` を新設。
`static func normalize(inputURL: URL) throws -> URL`（一時ディレクトリに出力した `.aac` の URL を返す）。

- **2 パス・チャンク処理**（メモリ一定）:
  1. 1 パス目: `AVAudioFile` で PCM をバッファ単位に読み、全体の RMS(dBFS) とピーク(dBFS) を集計
  2. 2 パス目: `framePosition = 0` に戻して再読、ゲインを掛けて出力ファイルへ書き出し
- **ゲイン計算（RMS ターゲット＋ピークキャップ）**: リミッター無しでクリップを防ぐ。
  - `gain = min(targetRMS − rms, peakCeiling − peak, maxGain)`
  - 目標 RMS: **-16 dBFS** / ピーク上限: **-1 dBFS** / 最大増幅: **+20 dB**（異常増幅の抑止）
  - 大きすぎる音源は負ゲインで下げる（ピーク上限超えも同式で必ず収まる）
- **出力形式: AAC（ADTS, `.aac`）**。文字起こし対応形式のうち、非可逆で十分小さく
  （FLAC/WAV は 14MB 上限にすぐ当たる）、`AVAudioPlayer` で再生可能なため。
  サンプルレート・チャンネル数は元を維持、ビットレートは 128kbps 目安。
  - 技術検証: `AVAudioFile(forWriting:)` の `.aac`（ADTS）書き出し可否を Phase 1 冒頭で確認。
    不可なら Audio Toolbox（`ExtAudioFile` + `kAudioFileAAC_ADTSType`）で書き出す。
- **エッジケース**:
  - 無音（ピークが実質 0）: 正規化スキップ（元データをそのまま保存）
  - デコード不能・失敗時: throw → 呼び出し側が元データ保存にフォールバック（現行動作維持）

### AudioFileImporter への組み込み

- `importFiles` を `async` 化し、`normalize: Bool` パラメータを追加する。
  正規化（デコード＋エンコード）はバックグラウンドで実行する
  （長尺ファイルで数秒かかり得るため、メインスレッドをブロックしない）。
- 流れ（`normalize == true` のとき）: セキュリティスコープ内で一時コピー →
  `AudioNormalizer.normalize` → 成功なら正規化済み `.aac` を、失敗なら元データを
  `AudioStorage.save` へ。`normalize == false` なら従来どおり元データをそのまま保存。
  `AudioClip.byteSize` は保存した実データのサイズ。モデル変更は不要。
- 呼び出し元 2 箇所を `Task { await ... }` に変更し、取り込み中はインジケータ表示
  （ボタン無効化＋`ProcessingIndicatorView` 相当の簡易表示）。
  `AddContentTypeView` の「取り込めたらフロー全体を閉じる」挙動は維持する。

### 正規化 ON/OFF のチェックボックス（取り込み確認シート）

正規化を行うかどうかはユーザーが取り込みごとに選べるようにする。
毎回の確認ダイアログではなく、**取り込み確認シート内の Toggle（チェックボックス）**方式を採る。

- `AudioImportLessonView`（ファイル選択直後に出る確認シート）に
  「Normalize volume」の Toggle セクションを追加する
  （`accessibilityIdentifier: "audioNormalizeToggle"`）。
- 選択値は `@AppStorage("audioImportNormalizeEnabled")` で永続化し、**既定 ON**。
  次回以降は前回の選択を初期値として引き継ぐ（毎回トグルし直さなくて済む）。
- `AddContentTypeView` 経由（レッスンの「＋ → Audio」）は現状ファイル選択後に即取り込みで
  確認ステップが無いため、こちらも `AudioImportLessonView` を経由させる。
  ただしレッスンは確定済みなので、レッスン固定モード（Picker を隠しレッスン名を表示）を
  `AudioImportLessonView` に追加して共用する。ファイル一覧の確認も兼ねられ、UI が統一される。
- 既存 UI テスト（`LessonAudioAddUITests`）はピッカー提示までの検証なので影響しない。

### スコープ外（将来拡張）

- 既存クリップの一括正規化（設定画面からの再処理）
- EBU R128 (LUFS) ベースのラウドネス正規化への置き換え
- TTS 音声（`TTSAudioStore`）はサーバ生成で音量が揃っているため対象外

## 影響範囲

- 新規: `ios/ESLLearningAssistant/Sources/Support/AudioNormalizer.swift`
- 変更: `ios/ESLLearningAssistant/Sources/Support/AudioFileImporter.swift`
  （async 化・`normalize:` パラメータ・正規化組み込み）
- 変更: `ios/ESLLearningAssistant/Sources/Views/AudioImportLessonView.swift`
  （Normalize volume Toggle 追加・レッスン固定モード追加）
- 変更: `ios/ESLLearningAssistant/Sources/Views/AddContentTypeView.swift` /
  `AudioLibraryView.swift`（async 呼び出し＋取り込み中 UI。AddContentTypeView は
  取り込み前に AudioImportLessonView（レッスン固定）を経由するフローに変更）
- 間接: 取り込み後の拡張子が `.aac` に変わるため、`RemoteTranscriptionTranslationService` の
  対象形式・`AVAudioPlayer` 再生はそのまま動く（どちらも対応済み形式）。既存クリップは無変更。

## テスト方針

- 新規 `AudioNormalizerTests`（合成 WAV をテスト内で生成して使用）:
  - 小音量 sine 波（振幅 0.05）→ 正規化後 RMS が目標近傍・ピークが -1 dBFS 以下
  - 大音量音源 → ゲインが負方向にも働きピーク上限内に収まる
  - 無音 WAV → スキップ（元のまま）/ 壊れたデータ → throw
  - 出力 `.aac` が `AVAudioFile` で開けて長さが概ね一致する
- `xcodebuild` でビルド＋既存ユニットテストが通ること。
- シミュレータ実機確認:
  - Toggle ON（既定）で小さい音量の音声を Files から取り込み → 再生音量が上がっている、
    取り込み中インジケータが出る、m4a 取り込み → 文字起こしが通ること
  - Toggle OFF で取り込み → 元ファイルがそのまま保存される（拡張子・サイズ不変）こと
  - Toggle の選択が次回の取り込みシートに引き継がれる（@AppStorage）こと
  - レッスンの「＋ → Audio」経由でも確認シート（レッスン固定）が出て取り込めること

## Phase 分割

- **Phase 1**: `AudioNormalizer` 本体（2 パス分析＋ゲイン適用＋AAC 書き出し。冒頭で
  `.aac` 書き出しの技術検証）＋ `AudioNormalizerTests`
- **Phase 2**: `AudioFileImporter` への組み込み（async 化・`normalize:` パラメータ・
  失敗時フォールバック）と呼び出し元 2 箇所の対応＋取り込み中 UI
- **Phase 2.5**: 正規化 ON/OFF チェックボックス（`AudioImportLessonView` に Toggle＋
  @AppStorage 永続化、AddContentTypeView をレッスン固定シート経由に変更）
- **Phase 3**: シミュレータ/実機での動作確認（音量・文字起こし・回帰）と後片付け
  （TODO/DONE 更新、プランのアーカイブ）
