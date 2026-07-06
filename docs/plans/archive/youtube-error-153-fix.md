# レッスンの YouTube 再生でエラー153（動画プレイヤーの設定エラー）を修正

## 目的・背景

レッスンコンテンツの YouTube を開くと、埋め込みプレイヤーが
「エラー153 動画プレイヤーの設定エラー」を表示して再生できない。

原因は 2025 年後半に YouTube が導入した仕様変更。埋め込みプレイヤー
（IFrame Player）は、ホスト環境を HTTP `Referer` ヘッダで正しく名乗ることが
必須になった。`Referer` が空／不正だと 153 を返す。

現状の実装（`YouTubeDetailView.swift` の `EmbeddedWebView`）は、
`https://www.youtube-nocookie.com/embed/<id>` を **`WKWebView` のトップレベル
ナビゲーションとして直接 `load(URLRequest:)`** している。iframe ホストページを
介さないため有効な `Referer`/オリジンが無く、153 の典型トリガーになっている。

参考:
- https://simonwillison.net/2025/Dec/1/youtube-embed-153-error/
- https://teamdynamix.umich.edu/TDClient/30/Portal/KB/Article/14491/Fixing-YouTube-Player-Error-153-with-Referrer-Policy-Settings
- https://dev.to/davidvesely/fixing-youtube-error-153-in-ios-capacitor-apps-a-simple-proxy-solution-607

## 対応方針

トップレベル直リンクをやめ、iframe を埋め込んだ最小 HTML を
**有効な http(s) オリジンを `baseURL` に指定して `loadHTMLString`** で読み込む。
これで iframe に `Referer`/オリジンが渡り 153 を回避できる。

1. `EmbeddedWebView` を `url:` 直リンク読み込みから、embed URL を `src` に持つ
   iframe ホスト HTML の `loadHTMLString(_:baseURL:)` へ変更する。
   - `baseURL = https://www.youtube-nocookie.com`（iframe と同一オリジン）
   - `<meta name="referrer" content="strict-origin-when-cross-origin">` と
     iframe の `referrerpolicy="strict-origin-when-cross-origin"` を付与
   - `allow="... autoplay; encrypted-media; picture-in-picture ..."` と
     `allowfullscreen` を付与
   - videoID は不変なので `makeUIView` で1度だけ読み込む
     （`updateUIView` の URL 差分再読込は baseURL 方式では不要）
2. `YouTubeLink.embedURL` に `playsinline=1&rel=0` を付与し、iPhone で
   インライン再生・関連動画抑制を効かせる（videoID は既存検証で安全）。

## 影響範囲

- `ios/.../Views/YouTubeDetailView.swift`（`EmbeddedWebView` を HTML 埋め込み方式へ）
- `ios/.../Models/YouTubeLink.swift`（`embedURL` に再生パラメータ付与）

再生経路のみの変更。モデルスキーマ・保存・他コンテンツ種別（写真/Audio）に影響なし。

## テスト方針

- `xcodebuild` で BUILD 成功を確認。
- 実機/シミュレータでレッスン→YouTube 詳細を開き、153 が消え再生できることを確認。
- 既存ユニット/ UI テスト（`YouTubeURLTests` 等）が引き続き通ることを確認。
