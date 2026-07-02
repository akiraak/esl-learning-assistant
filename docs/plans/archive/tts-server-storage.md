# TTSデータのサーバ保存（単語詳細 Pronunciation / Meanings / Examples のサーバTTS再生）

## 目的・背景

現状の `POST /api/tts`（`backend/src/index.ts:259`, `backend/src/tts.ts`）は Gemini TTS で
毎回音声（WAV, 24kHz mono 16bit）を合成して返すだけで、サーバに音声データを保存していない。
同じテキストの再生でも毎回 Gemini API のコストとレイテンシ（数秒）がかかる。

また、単語詳細画面（`WordDetailView`）の英文読み上げは現在すべて端末内蔵TTS
（`SpeechService` / `AVSpeechSynthesizer`）で、Gemini TTS の高品質音声は使われていない。

本タスクでは:

1. サーバで合成したTTS音声を**ファイル＋DBに保存**し、同一テキストの2回目以降は
   保存済みデータを返す（Gemini再呼び出しなし）
2. 単語詳細の **Pronunciation（見出し語 `word.text`）・Meanings（`senses[].englishDefinition`）・
   Examples（`examples[].english`）**の英文をサーバTTSで生成・保存し、アプリで聞けるようにする
   （Pronunciation は 2026-07-02 ユーザー指定で追加）

### 方針の決定事項

- **生成タイミングはユーザー操作によるオンデマンド＋サーバ保存（キャッシュ）方式**とする。
  単語情報の生成時に全英文を事前一括合成する案もあるが、聴かれない音声にもコストがかかるため
  見送り
- **iOS側のUIは「生成ボタン → 生成中 → 再生ボタン」の明示フロー**（2026-07-02 ユーザー指定）。
  Meanings / Examples の各英文に、未生成なら生成ボタンを表示し、生成（サーバ合成＋端末保存）が
  終わったら再生ボタンに変化させる。`ttsEngine` 設定には従わない（サーバTTS専用の独立ボタン）
- **生成した音声は端末ローカルにも保存する**。「生成済み＝再生ボタン」の状態を画面再訪や
  オフライン時にも維持するため。サーバ保存はコスト削減（再インストール・別端末での再生成が
  Gemini再呼び出しなしで済む）とデータ管理（管理画面）を担う
- Pronunciation（見出し語）/ Meanings / Examples の既存の端末TTSスピーカーボタンは
  本ボタンに**置き換える**。コロケーション・類義語等の他の読み上げボタンは端末TTSのまま
  （TODO のスコープ外。同じ仕組みで後から拡張可能）

## 対応方針

### Phase 1: backend — `tts_audio` テーブルと音声ファイル保存

- `backend/src/config.ts` に `ttsDir = data/tts` を追加し、起動時に `mkdirSync`
  （`imagesDir` と同じパターン）
- `backend/src/db.ts` にテーブル新設:

```sql
CREATE TABLE IF NOT EXISTS tts_audio (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL,
  text TEXT NOT NULL,
  voice TEXT NOT NULL,              -- "chobi" | "naruko"
  model TEXT NOT NULL,              -- "flash" | "pro"
  text_hash TEXT NOT NULL UNIQUE,   -- sha256("voice|model|text")
  filename TEXT NOT NULL,           -- data/tts/<text_hash>.wav
  byte_size INTEGER NOT NULL
);
```

- `POST /api/tts` の処理をキャッシュ対応にする:
  1. `sha256(voice|model|text)` で `tts_audio` を検索
  2. ヒット & ファイル実在 → ファイルを読んで `audio/wav` で返す（Gemini呼び出しなし）
  3. ミス（行なし、またはファイル欠損の自己修復）→ `synthesizeSpeech()` で合成し、
     `data/tts/<hash>.wav` に書き込み・行をUPSERTしてから返す
- リクエスト/レスポンスの形は変えない（`{ text, voice, model }` → WAVバイト列）ため、
  `PhotoDetailView` のOCR本文読み上げも自動的に保存対象になる
- サイズ目安: 24kHz mono 16bit ≈ 48KB/秒。例文1文（〜5秒）で約240KB、
  OCR本文（上限2000字・数分）でも数MB。ローカルSQLite+ファイルで十分許容

### Phase 2: 管理画面 — TTS一覧（試聴・削除）

`backend/src/admin.ts` にナビ「TTS一覧」を追加:

- `GET /admin/tts`: 一覧テーブル（id / テキスト先頭を省略表示 / voice / model / サイズ /
  作成日時 / 試聴 / 削除）
- `GET /admin/tts/:id/audio`: 保存WAVを `res.sendFile` で返す（一覧の `<audio controls>` から再生。
  既存の `/admin/logs/:id/image` と同じパターン）
- `POST /admin/tts/:id/delete`: ファイルと行を削除して一覧へリダイレクト
  （form + confirm。削除後に同じテキストが再生されれば再合成・再保存される）

### Phase 3: iOS — WordDetailView の Meanings / Examples に生成→再生ボタン

- **`TTSAudioStore` を新設**（`Sources/Services/TTSAudioStore.swift`）:
  端末ローカルの音声ファイル置き場（`Application Support/tts/`。Cachesだと OS に消され
  「生成済み」状態が勝手に戻るため避ける）を管理する
  - キーはサーバと同じ `sha256(voice|model|text)`
  - `localURL(text:voice:model:) -> URL?`（存在チェック）、`save(data:text:voice:model:) -> URL`
- **`TTSPlaybackService` を新設**（`GeminiSpeechService` と同様の `AVAudioPlayer` ラッパー。
  ローカルファイルURLから再生する。`isSpeaking` / `stop()` / delegate で終了検知）
- **`TTSButton` を新設**し、Pronunciation（見出し語 `word.text`）・Meanings
  （`sense.englishDefinition`）・Examples（`example.english`）の既存 `SpeechButton` を
  置き換える。状態は3つ:
  1. **未生成**（`TTSAudioStore` にファイルなし）: 生成ボタン
     （例: `waveform.badge.plus` アイコン）。タップで生成開始
  2. **生成中**: `ProgressView`（スピナー）。多重タップは無視
  3. **生成済み**: 再生ボタン（`speaker.wave.2.fill`）。タップで再生、再生中は停止ボタン
     （`stop.fill`）——既存 `SpeechButton` と同じ作法
- 生成処理: `BackendAPI.post("api/tts", { text, voice, model })` を呼び
  （サーバ側で合成＋保存、2回目以降はサーバキャッシュ返却）、返ってきたWAVを
  `TTSAudioStore` に保存 → 状態を「生成済み」へ。voice / model は設定
  （`ttsVoice` / `ttsModel`）を使う
  - 失敗時（401含む）は alert 表示して「未生成」に戻す（`PhotoDetailView` の401作法に準拠）
- 画面表示時に各英文の `TTSAudioStore` 存在チェックで初期状態を決める
  （ファイル存在確認のみで軽量。画面再訪時は最初から再生ボタン）
- `onDisappear` で再生を停止する（端末TTSと同様）
- 留意点: 設定で voice / model を変えるとキーが変わるため、既存の英文は「未生成」表示に戻る
  （旧設定の音声ファイルは残るが実害なし。将来必要ならクリーンアップを検討）
- 他のボタン（見出し語・コロケーション等）は従来どおり `SpeechService`（端末TTS）

## 影響範囲

- backend: `src/config.ts`（`ttsDir`）、`src/db.ts`（`tts_audio` テーブル・CRUD）、
  `src/index.ts`（`/api/tts` キャッシュ分岐）、`src/admin.ts`（TTS一覧・試聴・削除、ナビ拡張）
- iOS: 新規 `Sources/Services/TTSAudioStore.swift` / `Sources/Services/TTSPlaybackService.swift`、
  `Sources/Views/WordDetailView.swift`（Meanings / Examples を `TTSButton` に置き換え）。
  `GeminiSpeechService`（PhotoDetailView用）は変更なし
- DB: 新テーブル `tts_audio`。新ディレクトリ `backend/data/tts/`
- 本番運用: Docker ボリューム（`backend/data`）に音声ファイルが増える。
  管理画面の削除で手動管理できる範囲とし、自動クリーンアップは今回入れない

## テスト方針

- backend（`tsc` ビルド後、curl で実キー確認）:
  - 同一テキストを2回POST → 1回目より2回目が大幅に高速で、`tts_audio` の行と
    `data/tts/` のファイルが1つだけであること
  - voice / model を変えると別ファイルが作られること
  - WAVファイルを手動削除してからPOST → 自己修復（再合成・再保存）されること
- 管理画面: 一覧表示・`<audio>` での試聴・削除→ファイルも消えることをブラウザで手動確認
- iOS: `xcodebuild` ビルド確認。可能なら `TTSAudioStore` のユニットテスト
  （保存→存在チェック→URL取得、voice/model違いで別キーになること）を追加。
  実機・シミュレータでの手動確認項目:
  - 未生成の英文に生成ボタンが出る → タップでスピナー → 再生ボタンに変化する
  - 画面を離れて再訪しても再生ボタンのままである（ローカル保存の永続確認）
  - 再生／停止のトグル、画面離脱時の停止
  - バックエンド停止・API Secret不一致時に alert が出て「未生成」に戻る
  - 実音声の確認はユーザーに依頼
