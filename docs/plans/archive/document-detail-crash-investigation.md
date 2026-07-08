# ドキュメント詳細画面クラッシュ 調査・修正（完了 2026-07-08）

## 結果サマリ

- 真因: MarkdownUI の `Text + Text` 連結 × 全単語リンク化による **`Text.resolve` の再帰スタックオーバーフロー**（実機のみ）。
- 修正: `MarkdownLite`（軽量 Markdown パーサ・新規）＋ `TappableMarkdown` を**1ブロック＝1つの `Text(AttributedString)`**
  描画に書き換え（連結ゼロ＝再帰なし）。Document/Photo/Audio の3画面に共通適用。
- 検証: 単体テスト29件 PASS（MarkdownLite 13件新規）／シミュレータで表示崩れなし／**実機（iPhone 14 Pro）で
  当該 PDF を開いても落ちないことを確認（2026-07-08 ユーザー確認）**。

## 症状（ユーザー報告）

1. Documents タブで PDF を追加。
2. 文字おこし（抽出）＋翻訳を実行 → 完了。
3. **少したった後にアプリが落ちた。**
4. その後 Documents タブから**そのファイルを開こうとすると毎回落ちる**（決定的・再現性あり）。

## 調査でわかった事実

- Documents 系の Swift コードに強制アンラップ（`!` / `try!` / `as!`）は無い。JSON デコードは do/catch、完了本文は `?? ""` でガード済み。
- 07-06 に実機で起きた過去クラッシュ（`~/Library/Logs/DiagnosticReports/Retired/ESLLearningAssistant-2026-07-06-*.ips`）は
  `AudioClip.processingStatus.getter` の `swift_dynamicCastFailure`（[[swiftdata-codable-migration-pitfall]] のマイグレ地雷）。
  **これは修正済み**（AudioClip は `processingStatusStorage` optional 方式）。**今回とは別件。**
- `Document` のenumは**エンティティと同一コミット（Phase 1 / 78e608b）で追加**されたため既存 NULL 行が無く、
  `fileKind`（非オプショナル直付け）・`processingStatus`（optional storage）とも materialize でクラッシュしない。
  → 今回のクラッシュは **SwiftData enum 地雷ではない**。
- pending（抽出前）では開けていた＝ `originalSection` のインライン `PDFViewer`（PDFKit）単体は問題なし。
- クラッシュ状態（`.completed`）だけに現れる描画は **`DocumentDetailView.completedExtract`（`DocumentDetailView.swift:191-210`）のみ**。

## 根本原因（実機クラッシュログで確定 2026-07-08）

`devicectl device copy from --domain-type systemCrashLogs` で実機（iPhone 14 Pro）の当日クラッシュを取得。
07-08 15:33 の3件すべて同一:

```
EXC_BAD_ACCESS (SIGSEGV) — "Thread stack size exceeded due to excessive recursion"
  SwiftUICore Text.resolve(into:in:with:)
  SwiftUICore ConcatenatedTextStorage.resolve(into:in:with:)   ← Text + Text + Text …
  SwiftUICore Text.Storage.resolve(into:in:with:)
  …（数百段の再帰）… → main thread stack overflow
```

**= `Text` の深いネスト連結（`ConcatenatedTextStorage` = SwiftUI の `Text + Text`）によるスタックオーバーフロー。**

原因の連鎖:
1. `completedExtract` の `TappableMarkdown(markdown: extractedText)` が `EnglishWordLink.linkedMarkdown` で
   **全単語を1語ずつ `[word](eslword://…)` リンク化**する（この文書で英文1段落が最大 **510語**）。
2. MarkdownUI 2.4.1 の `TextInlineRenderer.defaultRender`（`Renderer/TextInlineRenderer.swift:109`）は
   1段落を **インラインノード毎に `result = result + Text(...)`** で左畳み込みする。
   → 510語の段落は ~1000 個のインラインノード → **~1000 段の左ネスト `ConcatenatedTextStorage`**。
3. SwiftUI の `Text.resolve` はネスト1段につき再帰する。実機のメインスレッドスタックは **~1MB** のため
   数百〜千段でオーバーフローして `EXC_BAD_ACCESS`。

**シミュレータで再現しなかった理由**: シミュレータ（macOS プロセス）のメインスレッドスタックは **~8MB** で、
同じ再帰深さを吸収してしまう。実機の当該コンテンツを seed して DocumentDetailView を直接描画する再現を
シミュレータ（iPhone 17 Pro）で実施 → **正常描画・約400MB・約2秒・クラッシュせず**。よって当初の「大容量描画で OOM/
ウォッチドッグ」仮説は**棄却**。真因は描画“量”ではなく **`Text` 連結の再帰“深さ”**（＝1段落の語数×リンク化）。

- 翻訳側 `Markdown(translatedText)` はリンク化しない＝1段落のインラインノードが少なく浅いので安全。
- 同じ `TappableMarkdown` を使う Photo/Audio 詳細も**同型の潜在バグ**。1段落が十分長ければ実機で落ちうる
  （音声 transcript・写真OCRは段落が短めなので未顕在なだけ）。

## （棄却）当初の有力仮説

`completedExtract` は完了時に**抽出英文＋全訳の全文を MarkdownUI で一括描画**する。しかも：

- `TappableMarkdown(markdown: extractedText)` は `EnglishWordLink.linkedMarkdown` で**全単語を1語ずつ
  `[word](eslword://…)` にリンク化**してから `Markdown` に渡す（ノード数が単語数ぶん増える）。
- その計算は `TappableMarkdown.body` 内の**同期処理で、body 評価のたびに毎回**走る（メモ化なし）。
- 使用中の **swift-markdown-ui 2.4.1 は遅延描画しない**（全ブロックを一括生成）。`Form`/`Section` も遅延しない。
- backend の1リクエスト上限は `DOCUMENT_MAX_TOKENS = 16384`（抽出・翻訳それぞれ）。実 PDF では
  抽出+訳で ~13万字級の Markdown を1画面に展開しうる（抽出側は全単語リンク化でノードがさらに数千〜万規模）。
- さらに `completedExtract` と**同居**して `originalSection` のインライン `PDFViewer`（height 460, 実 `PDFDocument`）も
  同時に生きている（Audio 詳細には無い要素）。

結果として、実サイズの PDF では**メインスレッドの長時間ハング（ウォッチドッグ kill＝「少したった後に落ちた」）
または OOM** を起こしうる。`.completed` は永続化されるため、**再オープンのたびに同じ重い描画が走り毎回落ちる**。

Audio が落ちないのは、transcript が録音長で短め＋インライン PDF が無いため閾値に届かないから、で整合。

## クラッシュログ取得方法（記録）

`libimobiledevice`（idevicecrashreport 等）は新 CoreDevice ペアリングの当該端末を認識できない。
`xcrun devicectl device copy from --device <UDID> --domain-type systemCrashLogs --source / --destination <dir>`
で OS のクラッシュレポート（`.ips`）を丸ごと取得できた。`--domain-type appDataContainer --domain-identifier <bundleid>`
なら開発ビルドのアプリコンテナ（SwiftData ストア・原本 PDF）も取れる。

## 対応方針

真因は「1段落の `Text` 連結（`ConcatenatedTextStorage`）の再帰深さ」なので、**1段落あたりのインライン
`Text` 連結数を抑える**か、**連結を使わず1つの `Text(AttributedString)` にする**のが本質的な修正。

- **案A（推奨）**: タップ可能な抽出英文を MarkdownUI ではなく **1つの `Text(AttributedString)`** で描画する
  （`TappableEnglishText` 方式）。全単語リンクを1つの `AttributedString` の `.link` ラン列として持てば
  **連結ゼロ＝再帰なし**で、語数に依らず落ちない。見出し等のブロック書式は必要なら AttributedString 側の
  属性で最小限に再現（この文書の抽出英文は素の散文で `#`/`**` 無し）。翻訳側は現状の `Markdown` 据え置きで安全。
- 案B: MarkdownUI を維持しつつ**全単語リンク化をやめる**（プレーン Markdown 表示＋タップは別方式）。段落あたりの
  ノードが激減し落ちない。ただし単語タップの実装が別途必要。
- 案C: 段落を N 語ごとに小 `Text` へ分割して連結深さを上限化（MarkdownUI 維持だが本質的でなく脆い）。

Photo/Audio 詳細の `TappableMarkdown` も同じ地雷を持つため、案A を共通コンポーネント化して 3画面に適用するのが望ましい。
回帰テスト用に「1段落 500語超」を linkedMarkdown → 描画してもクラッシュしない、を実機相当（小スタックのスレッド）で検証する。
