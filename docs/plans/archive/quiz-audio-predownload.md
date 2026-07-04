# 単語クイズ開始前の音声一括ダウンロード（進捗バー付き）

## 目的・背景

復習クイズの音声出題は、出題テンポを優先してサーバTTSの生成/取得を待たず、
ローカルキャッシュが無ければ端末内蔵TTSにフォールバックしている
（`ReviewSessionView.playAudio`、`ios/.../Views/ReviewSessionView.swift:607-616`）。

本タスクでは、**セッション開始時に必要な音声データをすべてダウンロードしてから
クイズを始める**ようにし、ダウンロード中は進捗がわかるバーを表示する。
これにより音声問題は常にサーバTTS（AI音声）で再生される。

前提: [quiz-audio-ai-generation.md](quiz-audio-ai-generation.md) を先に実施する。

- クイズ音声のモデルは `flash` 固定（`AppSettingsKeys.quizTTSModel` = サーバ `QUIZ_TTS_MODEL`）
- サーバは問題生成時に音声をプリ合成済み → ダウンロードは基本キャッシュヒットで高速
- プリ合成前の既存単語も、`POST /api/tts` がキャッシュミス時にその場で合成して返すため
  自己修復される（初回だけダウンロードが遅くなるが、進捗バーで待てる）

### 方針の決定事項

- **ダウンロード対象は「このセッションで出題する問題」の音声だけ**にする。
  due 単語（最大20語）の全保存問題の audioText を落とすと最大 600件超になり、
  プリ合成前の単語では初回の合成待ちが非現実的なため。
  そのために、現在は出題直前に行っている問題選択（`pickQuestion`）を
  **セッション開始時に main キュー分まとめて確定**する方式へ変更する
- 再出題（retry）は従来どおり retry 時に選択するが、音声形式は
  「ローカルに音声が存在する問題」に限定する（追加ダウンロードはしない）
- ダウンロードに失敗したテキストを含む問題は、その単語の別形式に選び直す
  （どの単語にも非音声形式 tc1〜tc11 / tt1〜tt3 があるため、サーバ不達でも
  非音声形式だけでセッションを続行できる）。端末内蔵TTSフォールバックは
  最終安全網としてコード上は残す

## 対応方針

### Phase 1: iOS — セッション問題の事前確定

- `loadQuestions()`（`ReviewSessionView.swift:467`）の取得成功後に、
  main キューの各単語について現行 `pickQuestion`（`FormatSelector.select` の比率調整 +
  variant ランダム）を出題順に実行し、`[(word, ReviewQuestion)]` を確定する。
  `sessionCounts` を選択のたびに更新することで、現行の形式比率調整の挙動を維持する
- `advance()` は main キュー消費時は確定済みリストから取り出すだけにする。
  retry キューは従来どおり `pickQuestion` を retry 時に呼ぶが、
  候補を「`audioText == nil` または `TTSAudioStore.localURL != nil` の問題」に
  絞るフィルタを追加する
- 事前確定ロジックはテスト可能なようにViewから独立した型
  （例: `Support/ReviewSessionPlanner.swift`）に切り出す

### Phase 2: iOS — 音声一括ダウンロードと進捗バー

- 新規 `Services/QuizAudioDownloader.swift`:
  - 入力: 確定した問題の unique な `audioText` のうち
    `TTSAudioStore.localURL(text:model:)` が nil のもの（最大でも20件程度）
  - `BackendAPI.post("api/tts", { text, model: quizTTSModel })` → `TTSAudioStore.save`
    を **TaskGroup 並列2〜3** で実行（ファイル単位の完了数で進捗を報告。
    1件あたり数十〜240KB なのでバイト単位の進捗は不要）
  - 各件は失敗時に1回リトライ。最終的に失敗したテキストの集合を返す
  - `Task` キャンセルに対応（画面の Close で中断できるように）
- `ReviewSessionView` の状態遷移に「音声準備中」を追加:
  - `isLoading`（問題取得）→ **downloading（音声DL）** → 出題
  - ダウンロード画面: `ProgressView(value: completed, total: total)` のバー +
    「Preparing audio… 3/8」表示。対象0件なら即出題へ
  - 全件失敗（サーバ不達など）でもエラー画面にはせず、失敗テキストを含む問題を
    別形式に差し替えて開始する（Phase 1 の確定リストを更新。差し替え先も
    音声形式なら同様にローカル存在を要求する）
- `onDisappear` / Close でダウンロード `Task` をキャンセルする

### Phase 3: 仕上げ・テスト

- `playAudio` は確定済み問題のローカル音声を再生する前提に整理
  （`TTSAudioStore.localURL` → `TTSPlaybackService.play(url:)`、
  内蔵TTSフォールバックは最終安全網として存続）
- 事前確定・差し替えロジックのユニットテスト
  （形式比率が現行 `FormatSelector` の挙動と一致すること、
  音声DL失敗時に非音声形式へ差し替わること）
- 手動確認とアーカイブ

## 影響範囲

- iOS: `Views/ReviewSessionView.swift`（状態遷移・事前確定・DL画面）、
  新規 `Services/QuizAudioDownloader.swift`、新規 `Support/ReviewSessionPlanner.swift`、
  テスト追加
- backend: 変更なし（既存 `/api/tts` をそのまま利用。キャッシュミス時の
  その場合成が自己修復を兼ねる）

## テスト方針

- iOS ユニットテスト: `ReviewSessionPlanner`（事前確定・差し替え）、
  `QuizAudioDownloader` はキー計算・保存の統合部分を `TTSAudioStore` 経由で確認
- `xcodebuild` ビルド + 手動確認:
  - 初回（サーバキャッシュなしの単語）: バーが進み、完了後にクイズが始まり、
    音声問題がAI音声で再生される
  - 2回目以降: DLがほぼ瞬時にスキップされる（キャッシュヒット）
  - サーバ停止時: 音声形式が出題されず非音声形式でセッションが完走する
  - DL中に Close → 中断できる
