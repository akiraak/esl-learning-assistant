# Audio の英文文字起こしと日本語翻訳

## 目的・背景

Audio タブに取り込んだ音声（`AudioClip`）は現状「タイトル・レッスン紐付け・再生」だけの純メタデータで、
中身の英語を学習に使えない。写真コンテンツが OCR で英文文字起こし＋日本語翻訳されて
単語タップ登録まで繋がっているのに対し、音声は聞くだけになっている。

音声にも **英文の文字起こし（transcript）＋日本語全訳** を付け、写真詳細（`PhotoDetailView`）と
同じ体験（英文は `TappableMarkdown` で単語タップ登録、訳は Markdown 表示）を提供する。

これは「写真の OCR＋翻訳」の一番近い前例であり、その4層構成
（① SwiftData モデルに状態＋結果を持たせる → ② `@MainActor protocol` + `Remote…Service` で
backend 呼び出し → ③ pending/manual を状態遷移 → ④ 詳細 View が状態で分岐表示）を
ほぼそのまま複製する。

### 技術的な要点（調査で確定した事実）

- **Claude は音声入力不可**（SDK `ContentBlockParam` に audio ブロックが無い）。
  文字起こしは **Gemini（音声入力ネイティブ対応）** で行う。既存 `tts.ts` の raw fetch
  （`generateContent` + `inlineData`）を「音声出力」から「音声入力」へ反転して使う。
- **翻訳（英→日）は新規実装不要**。既存 `translateText(englishText, targetLanguage)`
  （`backend/src/ocrTranslate.ts:109`, 内部 `callStructured` + `TRANSLATE_SCHEMA`）を再利用する。
- → 最短構成は **「Gemini で 音声→英文」＋「既存 translateText で 英文→日本語」の2段**。

## 決定事項（ユーザー確認済み・2026-07-06）

1. **実行トリガ = 詳細画面の手動ボタン**。写真OCRのような取り込み時自動処理はしない
   （音声は長く・コストも高いため、クリップ単位でユーザーが「文字起こし」ボタンを押す）。
2. **v1 の対象は短いクリップのみ**。音声を base64 インラインで1回の Gemini 呼び出しに送る最小構成。
   Gemini のインライン上限（実質 ~15MB / ~15分）を超えるものは弾く。長尺（レッスン丸ごと 30〜60分）の
   File API アップロード＋分割は将来拡張として §将来拡張に残す。
3. **粒度 = 全文＋全文訳**（写真OCRと同じ）。タイムスタンプ付きセグメント（字幕同期）は将来拡張。

## 対応方針（アーキテクチャ）

```
[iOS] AudioDetailView「文字起こし」ボタン
   → RemoteTranscriptionTranslationService.process(clip)
        clip.processingStatus = .processing
        AudioStorage で音声ファイル読込 → base64
        BackendAPI.post("api/transcribe-translate", { audioBase64, mediaType, targetLanguage }, timeout: 180)
   ↓
[backend] POST /api/transcribe-translate
        transcribe.ts: Gemini generateContent (inlineData: audio + "Transcribe verbatim") → 英文
        translateText(英文, targetLanguage)  ← 既存流用（Claude）
        コスト記録（Gemini分＋Claude分を分けて log）
        → { englishText, translatedText, translationLanguage }
   ↓
[iOS] clip.transcriptText / translatedText / translationLanguage に保存 → .completed
        AudioDetailView が transcript セクションを状態分岐で表示
```

## 影響範囲

### バックエンド（`backend/src/`）
- `config.ts` … `transcriptionModel`（Gemini）と `audioDir` を追加
- `pricing.ts` … transcription モデルの単価を登録（未登録だと `estimateCostUsd` が 0 を返す）
- `transcribe.ts`（新規）… Gemini 音声→英文
- `ocrTranslate.ts` … `translateText` を再利用（変更なし想定）
- `index.ts` … `POST /api/transcribe-translate` を追加
- `db.ts` … `transcription_requests` ログテーブルを追加（`requests` / `tts_audio` に倣う）
- `admin.ts` … `NavSection`/`NAV_ITEMS` に "transcriptions" を追加し一覧＋音声試聴＋コスト表示
- `.env.example` … Gemini モデル変数を追記

### iOS（`ios/ESLLearningAssistant/Sources/`）
- `Models/AudioClip.swift` … `AudioProcessingStatus` enum ＋ 結果フィールド群を **optional/default で** 追加
- `Services/TranscriptionTranslationService.swift`（新規, protocol）
- `Services/RemoteTranscriptionTranslationService.swift`（新規, `RemoteOCRTranslationService` の音声版）
- `Views/AudioDetailView.swift` … transcript セクション（状態分岐UI・手動ボタン）を追加
- `Views/ProcessingIndicator.swift` … `PhotoProcessingView` のラベルを汎用化 or 音声用ビュー追加（再利用）
- `Views/AudioView.swift`（任意）… `AudioClipRow` に文字起こし状態の小さなインジケータ
- `BackendAPI` は **無改修で再利用**（新しい path を渡すだけ。timeout は長めに指定）

### 変更不要（重要）
- **ModelContainer の schema 登録は変更不要**（`AudioClip` は既に
  `ESLLearningAssistantApp.swift` / `ContentView.swift` 両方に登録済み）。フィールド追加のみ。
- `AudioStorage` / 取り込みフロー / 再生（`TTSPlaybackService` / `TTSPlayerBar`）は変更なし。

## マイグレーション上の注意

- `AudioClip` への新フィールドは **必ず optional か default 付き** で追加し、既存ストアの
  ライトウェイトマイグレーションを維持する（結果系 `transcriptText?` 等は optional、
  `processingStatus` は `= .pending` の default 付き non-optional ＝ `Word.aiInfoStatus` 前例と同型）。
- `processingStatus` の enum は写真OCR同様 `String, Codable` を **ラッパ無しで直接** @Model に宣言し
  SwiftData にネイティブ保存させる（rawValue 手動ストレージは不要）。
- ※埋め込み Codable の CodingKeys リネーム地雷／非オプショナル追加地雷（過去の被弾）は、
  今回スカラー @Model プロパティのみ・optional/default 追加なので回避済み。

## リスク・検討点

- **音声サイズと 20MB JSON 上限**: `express.json({ limit: "20mb" })` と Gemini インライン上限に対し、
  base64 は元データの約1.33倍に膨らむ。iOS 側で **送信前にバイト数チェック**し、超過は
  「短いクリップに分割してください」旨のわかりやすいエラーにする（サーバ側でも 400 で弾く）。
- **対応 mimeType**: Gemini がサポートする音声形式（`audio/wav`, `audio/mp3`, `audio/aac`,
  `audio/ogg`, `audio/flac` 等）に限定。iOS は取り込みファイルの拡張子から mimeType を導出し、
  未対応拡張子は事前にエラー表示。
- **コスト**: 音声はトークン換算（≈ 秒数課金）。`pricing.ts` への単価登録を忘れると料金が 0 表示になる。
- **処理時間**: 音声アップロード＋文字起こしは 60 秒を超えうるため、iOS の `BackendAPI.post` に
  `timeout: 180` を指定（イラスト生成で既にある延長パターンを踏襲）。
- **キャッシュ方針**: 写真OCRと同じく **サーバキャッシュは持たない**（結果は `AudioClip` に保存）。
  `transcription_requests` は料金・履歴のログ用途のみ（管理画面表示のため）。

## Phase / Step

### Phase 1: バックエンド — 文字起こしAPI ✅ 完了（2026-07-06）
- [x] `config.ts` に `transcriptionModel`（`GEMINI_TRANSCRIPTION_MODEL ?? "gemini-2.5-flash"`）と
      `audioDir` を追加。`db.ts` の `fs.mkdirSync` 群に `audioDir` を追加
- [x] `pricing.ts` の単価表に transcription モデルを登録（`DEFAULT_TRANSCRIPTION_PRICING`:
      `gemini-2.5-flash` 音声入力 $1.00 / テキスト出力 $2.50。currentPricing init と restorePricing にも合流）
- [x] `transcribe.ts`（新規）: `tts.ts` `synthesizeChunk` を反転した Gemini `generateContent`
      呼び出し（`inlineData: { mimeType, data: audioBase64 }` ＋ 逐語文字起こしプロンプト、テキスト出力）。
      思考は `thinkingBudget: 0` で無効化。fetch/リトライ/timeout/`usageMetadata` 抽出は流用。
      戻り値 `{ englishText, inputTokens, outputTokens }`。対応 mimeType 判定＋拡張子マップも同ファイル
- [x] `index.ts` に `POST /api/transcribe-translate` を追加（`/api/ocr-translate` を雛形）。
      `{ audioBase64, mediaType, targetLanguage }` を検証（mimeType・14MBサイズ上限）→ 音声を `audioDir` 保存 →
      `transcribeAudio()` → 既存 `translateText()`（export 化）→ コストを Gemini分/Claude分に分けて記録 →
      `{ englishText, translatedText, translationLanguage }` を返す。`express.json` 上限は 25mb に引き上げ
      （14MB ガードが 413 より先に働くため）
- [x] `db.ts` に `transcription_requests` ログテーブル（`requests` に倣う）＋ insert/list/get 関数
- [x] `.env.example` に `GEMINI_TRANSCRIPTION_MODEL` を追記
- [x] `tsc` ビルド確認、`curl` で実 Gemini に英語音声（/api/tts 生成の WAV）を投げて
      英文逐語文字起こし＋日本語訳・コスト記録・各種バリデーション（400/401/413）を確認

### Phase 2: iOS — モデル拡張 ✅ 完了（2026-07-06）
- [x] `AudioClip.swift` に `AudioProcessingStatus`（`String, Codable`: pending/processing/completed/failed）と
      `processingStatus`（`= .pending`）/ `processingErrorMessage: String?` / `transcriptText: String?` /
      `translatedText: String?` / `translationLanguage: String?` を追加（optional/default でマイグレーション安全）。
      `processingStatus` は `Word.aiInfoStatus` と同型の `var … = AudioProcessingStatus.pending`（プロパティ既定値付き non-optional）
- [x] ビルド確認（`xcodebuild` BUILD SUCCEEDED、schema 登録は変更不要）＋ 既存ストアの起動確認。
      旧スキーマの実ストア（Lesson データ有り）を新ビルドで開き、ライトウェイトマイグレーションで
      5カラム（`ZPROCESSINGSTATUS`/`ZPROCESSINGERRORMESSAGE`/`ZTRANSCRIPTTEXT`/`ZTRANSLATEDTEXT`/`ZTRANSLATIONLANGUAGE`）が
      追加され、既存 Lesson が保持されたまま起動する（`StoreLoadErrorView` に落ちない）ことをシミュレータで確認

### Phase 3: iOS — サービス層
- [ ] `TranscriptionTranslationService`（protocol, `@MainActor func process(_ clip: AudioClip) async`）
- [ ] `RemoteTranscriptionTranslationService`（`RemoteOCRTranslationService` の音声版）:
      `.processing` へ → `AudioStorage` で音声ロード → 拡張子→mimeType 変換 →
      `BackendAPI.post("api/transcribe-translate", body, timeout: 180)` → デコード →
      結果を `clip` に保存 → `.completed` / 失敗は `.failed` ＋ メッセージ

### Phase 4: iOS — 詳細画面UI
- [ ] `AudioDetailView` に **Transcript セクション** を追加し `processingStatus` で分岐:
      未実行=「文字起こし」ボタン / processing=`ProcessingIndicator`（明滅＋Shimmer）/
      failed=エラー＋retry / completed=`TappableMarkdown(transcriptText)` ＋ `Markdown(translatedText)` ＋
      再文字起こしボタン
- [ ] `ProcessingIndicator.swift` の `PhotoProcessingView` ラベルを汎用化 or 音声用ラベルで再利用
- [ ] （任意）`AudioClipRow` に文字起こし状態の小さなインジケータ
- [ ] `xcodebuild` ビルド確認

### Phase 5: バックエンド管理画面
- [ ] `admin.ts` の `NavSection`/`NAV_ITEMS` に "transcriptions" を追加し、一覧ページ
      （日時/音声試聴/英文/訳/トークン/コスト/削除）を TTS 一覧（`admin.ts:908`）に倣って実装
- [ ] 音声配信ルート（`/admin/transcriptions/:id/audio`）を TTS の配信ルートに倣って追加

### Phase 6: 検証・仕上げ
- [ ] backend: 実 Gemini で英語音声 → 英文文字起こし＋日本語訳、料金記録、管理画面表示を確認
- [ ] iOS: `AudioDetailView` の状態遷移（未実行→処理中→完了/失敗→retry）を確認。
      可能なら service をスタブ化した UITest / ユニットテストを追加
- [ ] specs 更新（`docs/plans/archive/app-spec.md` の Audio 節、`data-model.md` に `AudioClip` の
      transcript フィールド追加）
- [ ] 単語タップ登録が transcript 英文でも機能することを確認（`TappableMarkdown` の紐付け先は
      `WordOccurrence` の source をどうするか＝AudioClip 由来。sourcePhoto 相当が無い点だけ要確認）

## 将来拡張（v1 では対象外）
- 長尺録音対応（Gemini File API アップロード＋チャンク分割・非同期処理）
- タイムスタンプ付きセグメント（再生位置に同期する字幕／カラオケ表示）
- 取り込み時の自動文字起こし（写真OCRと同型のバックグラウンド一括処理）
- 文字起こし結果のサーバキャッシュ（`sha256(model|audioHash|targetLanguage)`）
