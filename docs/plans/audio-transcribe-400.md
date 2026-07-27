# アプリで音声ファイルの文字起こしをすると400エラー

## 結論（原因確定）

**コードのバグではない。本番サーバー（esl.chobi.me）の `GEMINI_API_KEY` が無効。**

アプリに出た実際の文言:

```
Server error (HTTP 500): gemini transcribe: failed after 3 attempts:
HTTP 400: {"API key not valid. Please pass a valid API Key"}
```

この 400 は **アプリ → 自前 backend** の 400 ではなく、**backend → Gemini API** の 400。
`transcribe-translate` 自体は HTTP 500 を返している（`backend/src/index.ts:333-336`）。

## 調査経緯

- iOS: `RemoteTranscriptionTranslationService.swift`
  - `POST /api/transcribe-translate` に `{audioBase64, mediaType, targetLanguage, title}` を JSON 送信
  - 形式（wav/mp3/aac/aif/aiff/ogg/flac）とサイズ（14MB）は**送信前にローカルで弾く**ため、
    backend 側の 400 分岐（6 種）はそもそも発火しにくい
- backend `index.ts:206-337` の 400 分岐は
  `audioBase64 is required` / `mediaType must be one of` / `targetLanguage is required` /
  `title must be a string` / `audioBase64 is not valid base64 audio` / `audio too large` の 6 つのみ
  → いずれにも該当しなかった
- 音声形式の疑いは**否定済み**: 取り込み時ノーマライズ後と同じ ADTS AAC（および m4a）を
  ローカルの `GEMINI_API_KEY` で `gemini-2.5-flash` に直接投げたところ **両方 HTTP 200** で文字起こし成功。
  → 形式・ノーマライズ処理は無関係。ローカルの Gemini キーは有効
- 本番は Cloudflare Tunnel 経由の別 Docker コンテナで、環境変数は
  `g3plus-ops/esl-learning-assistant/.env`（正本は Sx360 側、サーバ配置先は
  `/home/ubuntu/g3plus-ops/esl-learning-assistant/.env`）。ここの `GEMINI_API_KEY` が
  失効／別プロジェクトのキー／制限付きになっている
  - なお `GEMINI_API_KEY` が**未設定**なら `transcribe.ts:104-106` が
    "GEMINI_API_KEY is not set" を投げるので、「設定はされているが無効」の状態

## 対応（本番サーバー側の作業。このMacからはSSH鍵が無く実行不可）

`g3plus-ops/docs/workflows/esl-learning-assistant.md` の「デプロイ設定の更新」に従う。

```bash
# 1. Sx360 の /home/ubuntu/g3plus-ops/esl-learning-assistant/.env の
#    GEMINI_API_KEY を有効なキーに書き換える
# 2. 転送して再起動
scp -i /home/ubuntu/.ssh/id_rsa_nopass \
  /home/ubuntu/g3plus-ops/esl-learning-assistant/.env \
  ubuntu@g3plus.lan:/home/ubuntu/g3plus-ops/esl-learning-assistant/
ssh -i /home/ubuntu/.ssh/id_rsa_nopass ubuntu@g3plus.lan \
  'docker compose --project-directory /home/ubuntu/g3plus-ops/esl-learning-assistant up -d'
```

### 併せて確認すべきこと

- **同じキーを使う `/api/tts`（Gemini TTS）も本番で失敗しているはず**。復旧後に併せて確認する
- ローカル `backend/.env` の `GEMINI_API_KEY` は有効なので、それを本番へ流用してもよい

## 残課題（任意・別タスク候補）

エラーメッセージが原因究明を妨げた点が2つある。

1. `transcribe.ts:167` が常に `failed after ${TRANSCRIBE_RETRIES} attempts` と出す。
   4xx は 1 回目で break する（`:137`）ので「3回試した」は事実と違う。実試行回数を出すべき
2. 認証エラー（Gemini 400 "API key not valid"）が backend の 500 に包まれて出るため、
   アプリ側の表示が「400 なのか 500 なのか」分かりにくい。
   上流 API のキー不正は専用メッセージ（例: "Gemini API key is invalid (server config)"）に
   したほうが運用上わかりやすい

## テスト方針

- 本番キー差し替え後、アプリで音声取り込み → 文字起こしが成功すること
- `/admin` の文字起こしログに success で記録されること
