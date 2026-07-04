# 単語問題の音声生成をAIで行う（クイズ音声のサーバTTSプリ合成）

## 目的・背景

復習クイズの音声出題（`audioText` を持つ形式: vc1〜vc7 / vtc1 / vtt1 / vt1 / vt2）は、
現状 iOS 側で「サーバTTSのローカルキャッシュがあれば再生、無ければ端末内蔵TTS
（`AVSpeechSynthesizer`）にフォールバック」している
（`ReviewSessionView.playAudio`、`ios/.../Views/ReviewSessionView.swift:609`）。

ローカルキャッシュは `WordDetailView` でユーザーが明示的に生成した英文にしか存在しないため、
クイズの音声は実質ほぼ端末内蔵TTSで読み上げられており、AI音声（Gemini TTS）の品質が
活かせていない。quiz-questions-server-storage.md 時点では「TTS 音声の事前合成はしない」
としていたが、本タスクでこれを転換し、**クイズ問題の音声をサーバ側で AI 生成（事前合成）する**。

前提となる既存基盤:

- `POST /api/tts`（`backend/src/index.ts:468`）: `sha256("model|text")` キーで
  `tts_audio` テーブル + `data/tts/<hash>.wav` にキャッシュ。キャッシュミス時は
  2キャラからランダム選択して Gemini TTS 合成（tts-random-voice.md）
- クイズ問題は `POST /api/quiz-questions/generate`（`index.ts:322`）と
  管理画面 `POST /admin/quiz-questions/regenerate`（`backend/src/admin.ts:1312`）の
  2経路で生成され、どちらも `generateQuizQuestions` → `replaceQuizQuestions` を呼ぶ
- iOS のローカル音声キャッシュ `TTSAudioStore` はサーバと同一キー `sha256("model|text")`

### 方針の決定事項

- **生成タイミング**: クイズ問題の生成成功直後に、サーバ側で fire-and-forget の
  バックグラウンド処理として全 `audioText` を一括合成する（レスポンスはブロックしない。
  問題生成だけでも数十秒かかるため、音声合成完了を待たせない）
- **クイズ音声の TTS モデルは "flash" 固定**とする（サーバ・iOS 両方に定数で持つ）。
  - 理由: キャッシュキーに model が含まれるため、iOS 側がユーザー設定 `ttsModel` を
    使うとサーバのプリ合成キーと不一致になり事前合成が無駄になる。クイズの音声は
    短文なので flash で十分・低コスト
  - `ttsModel` 設定（local/flash/pro）は WordDetailView / PhotoDetailView 用に存続
- **既存単語のバックフィルは行わない**。プリ合成前の問題・過去の生成失敗分は、
  後続タスク（quiz-audio-predownload.md）のセッション開始時ダウンロードで
  `/api/tts` がキャッシュミス時に合成する自己修復に任せる。手動では管理画面の
  再生成ボタンでも埋められる

## 対応方針

### Phase 1: backend — TTS合成＋キャッシュ処理の関数化

`/api/tts` ハンドラ内にべた書きされているキャッシュ検索→ランダムボイス選択→合成→
ファイル/DB保存の一連の処理（`index.ts:487-518`）を再利用可能な関数に切り出す。

- 新規 `backend/src/ttsStore.ts`:
  - `getOrSynthesizeTtsAudio(text: string, model: ModelKey): Promise<Buffer>`
    1. `sha256("model|text")` で `getTtsAudioByHash` を検索
    2. ヒット & ファイル実在 → ファイルを読んで返す（Gemini呼び出しなし）
    3. ミス / ファイル欠損 → ランダムボイスで `synthesizeSpeech` → `data/tts/<hash>.wav`
       書き込み + `upsertTtsAudio` → 返す
  - ログ（cache hit / start / success / failed）も現行フォーマットのまま移設
- `/api/tts` は入力検証 + この関数呼び出し + WAVレスポンスに縮退。**挙動は不変**

### Phase 2: backend — クイズ問題生成後の音声プリ合成

- `ttsStore.ts` に `pregenerateQuizAudio(questions: QuizQuestion[]): Promise<void>` を追加:
  - `audioText` が非 null の問題から **unique なテキスト**を抽出
    （vc1/vc2/vc5/vt1 などは audioText が見出し語そのもので重複するため、
    実質 1単語あたり 20前後のテキスト）
  - `QUIZ_TTS_MODEL = "flash"` 定数で `getOrSynthesizeTtsAudio` を**並列2**（`tts.ts` の
    チャンク合成と同程度の控えめな並列度）で実行
  - 1テキストの失敗は他に影響させず、最後に成功数/失敗数/合計コストを logger に出す
- 呼び出し箇所（2経路とも `replaceQuizQuestions` の直後に `void pregenerateQuizAudio(...)`）:
  - `POST /api/quiz-questions/generate`（`index.ts:405` 付近）
  - `POST /admin/quiz-questions/regenerate`（`admin.ts:1357` 付近）
- 同一単語の生成を連打した場合の同一テキスト二重合成は許容する
  （キャッシュキーが同じなので上書き保存になるだけで実害なし。個人開発用途のため
  in-flight 管理は入れない）

### Phase 3: iOS — クイズ音声モデルを flash 固定に

- `AppSettingsKeys` に `quizTTSModel = "flash"` 定数を追加
  （サーバの `QUIZ_TTS_MODEL` と一致させる旨をコメントに明記）
- `ReviewSessionView.playAudio`（`ReviewSessionView.swift:609`）の
  `serverModel`（`ttsModel == "local" ? fallback : ttsModel`）の決定を廃止し、
  `TTSAudioStore.localURL(text:model: AppSettingsKeys.quizTTSModel)` に固定
- `@AppStorage(AppSettingsKeys.ttsModel)`（`ReviewSessionView.swift:27`）が
  不要になれば削除
- 端末内蔵TTSへのフォールバック（`SpeechService.speak`）は本タスクでは残す
  （プリ合成前の既存単語のため。ダウンロード導入後の扱いは quiz-audio-predownload.md）

## 影響範囲

- backend: 新規 `src/ttsStore.ts`、`src/index.ts`（`/api/tts` の縮退、
  `/api/quiz-questions/generate` へのフック）、`src/admin.ts`（regenerate へのフック）
- iOS: `Support/AppSettingsKeys.swift`、`Views/ReviewSessionView.swift`
- データ: `data/tts/` の WAV が単語ごとに約20ファイル（短文 WAV ≈ 数十〜240KB/件）増える
- コスト: flash の短文合成 × 20前後/単語。バックグラウンドで 1単語あたり1分前後

## テスト方針

- backend: `npm run build`（型チェック）。サーバ起動 + curl で
  `/api/quiz-questions/generate`（regenerate: true）→ ログにプリ合成の成功数が出て、
  `data/tts/` と `tts_audio` に音声が増えること。同じ単語を再生成 → 全件キャッシュヒットで
  Gemini 呼び出しが発生しないこと。`/api/tts` 単体の挙動（キャッシュヒット/ミス）が
  従来どおりであること
- iOS: `xcodebuild` ビルド確認。実機/シミュレータで、プリ合成済みの単語の音声問題が
  AI音声（サーバTTS）で再生されることを手動確認（音質の判別はユーザーに依頼）
- 管理画面: 単語一覧の「生成」ボタンからの生成でも音声がプリ合成されること
