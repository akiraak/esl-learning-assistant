# ドキュメント（PDF / Word）読み込み

TODO 由来: `- ped, doc 読み込み`

**決定事項（すべて確定）**

- **対象形式**: PDF（`.pdf`）と Word（`.docx`）。レガシー `.doc` は対象外。
- **テキスト処理**: ハイブリッド。埋め込みテキスト抽出を優先し、テキスト層が無い（スキャンPDF等）場合は画像OCRにフォールバック（§2.2）。
- **抽出＋翻訳のトリガー**: **v1 は詳細画面の手動ボタン**（音声と同じ）。ただし**後から取り込み時自動へ切替可能な実装**にする（抽出＋翻訳を独立サービスに切り出し、呼び出し箇所を差し替えるだけで自動化できる形にする。§5）。
- **所属単位**: **ライブラリ型（音声＝`AudioClip` と同型）**。レッスン非依存・多対多・nullify（§2.3）。
- **DOCX 表示**: QuickLook で十分（§4.5）。backend での DOCX→PDF 変換は将来拡張。
- **アプリ内ファイル表示**: 取り込んだ文書を**アプリ内でそのまま閲覧**できるようにする（§4.5）。

## 1. 目的・背景

ESL の授業では、教科書ページの撮影（3.1 OCR）や配布音声（3.5 Audio）に加え、**プリント配布が PDF / Word 文書**で行われることが多い。現状これらは「写真に撮る」以外に取り込み手段が無く、テキスト層を持つ文書でも一度画像化する必要があり非効率。

そこで **PDF / Word 文書を新しいコンテンツタイプとして取り込み**、文字起こし・翻訳済みテキストを既存の学習動線（3.1 写真詳細 / 3.5 音声詳細と同じ「英文タップ→単語帳登録」「訳の Markdown 表示」「問題生成の素材」）に接続する。

## 2. 対応方針

### 2.1 全体像（既存パターンの踏襲）

音声（`AudioClip`）で確立した **4層構成**をそのまま踏襲する:

1. 状態＋結果を持つモデル（`Document`） … §Phase 1
2. iOS → backend の Remote サービス（抽出＋翻訳エンドポイント） … §Phase 2
3. 取り込み → `processing` → `completed`/`failed` の状態遷移 … §Phase 3
4. 詳細 View で状態分岐表示（英文タップ登録／訳 Markdown） … §Phase 4

コンテンツ追加の入口 `AddContentTypeView`（現状 Photo / Audio / YouTube の3択）に **「Document」を4つ目**として追加する。

### 2.2 抽出方針（ハイブリッド）

抽出・翻訳・OCRフォールバックは、既存の `/api/ocr-translate`・`/api/transcribe-translate` と同様に **すべてサーバ側**に置く（iOS はファイルを base64 で送るだけ。AI キーや重い依存を iOS に持たせない）。

- **Word（.docx）**: サーバで zip 展開 → `word/document.xml` からテキスト抽出（例: `mammoth` 等）。
- **PDF（テキスト層あり）**: サーバでテキスト抽出（例: `pdf-parse` 等）。
- **PDF（テキスト層なし＝スキャン画像）**: サーバで各ページを画像化し、既存 `ocrAndTranslate`（`/api/ocr-translate` の内部関数）を**ページ単位で再利用**して OCR。ページ結果を連結する。
- 抽出した英文は、既存 `translateText`（`/api/ocr-translate` 内で使う英→目的言語翻訳）を再利用して翻訳する。
- 判定: ドキュメント全体でテキスト抽出結果が実質空ならスキャンとみなし OCR 経路へ。**v1 はドキュメント単位の二択**（ページごとの混在処理はしない）。混在文書・長尺分割は将来拡張。

> 代替案（不採用）: iOS 側 PDFKit でローカル抽出/画像化。ローカルで完結でき安価だが、DOCX をネイティブに扱えず、音声・写真と経路が分かれて一貫性を欠くため不採用。サーバ集約を採る。

### 2.3 データの所属

**`AudioClip` と同型のライブラリ**とする。レッスンに**従属せず**、0個以上のレッスンへ紐付けられる（多対多・削除時は nullify）。レッスン非依存のライブラリ文書も許容し、レッスンをまたいで使い回せる。inverse は `Lesson.documents` 側で定義する。データモデル上は §4.5 `AudioClip` をほぼそのまま踏襲する。

## 3. データモデル（Phase 1 詳細）

新エンティティ `Document`（**`AudioClip` を範に取る**。§4.5 とほぼ同型）:

| フィールド | 型 | 用途 |
| --- | --- | --- |
| id | UUID | |
| title | String | 表示名。既定は取り込みファイル名から拡張子を除いたもの（`AudioClip.title` と同じ）。編集可 |
| documentFileName | String | `Documents/Documents/` 配下の実ファイル名（`UUID.ext`、本体はDB外） |
| fileKind | DocumentKind (enum: pdf / docx) | ビューア出し分け・抽出経路の判定に使用 |
| sourcePath | String? | 取り込み元参照用の予備（ファイル取り込みでは nil。`AudioClip.sourcePath` と同じ） |
| byteSize | Int | |
| importedAt | Date | |
| lessons | [Lesson] = [] | 紐付くレッスン（0個以上、多対多・nullify）。inverse は `Lesson.documents` |
| processingStatusStorage → processingStatus | DocumentProcessingStatus? → computed | `AudioClip` と**同じ storage + computed 方式**。実ストレージは optional（NULL 許容）にし、公開 API は computed で NULL を `.pending` として返す（**[[swiftdata-codable-migration-pitfall]]** 回避。非オプショナル enum 直付けは旧行 materialize でクラッシュする） |
| processingErrorMessage | String? | エラー時のユーザー向け文言（401時のAPI Secret案内など。optional追加で軽量マイグレーション維持） |
| extractedText | String? | 抽出/OCRされた英文（`AudioClip.transcriptText` に相当） |
| translatedText | String? | 翻訳結果（Markdown） |
| translationLanguage | String? | 訳の言語コード（例 `ja`） |

- **[[ios-swiftdata-new-entity-checklist]]** に従い、全 `ModelContainer`（本体・プレビュー・テスト）へ `Document.self` を登録し、`DebugDataCleaner` に削除対象として追加する。
- `Lesson` に `documents: [Document]`（多対多・nullify、`audioClips` と同様に所有しない inverse）を追加する。
- `WordOccurrence` に **`sourceDocument?: Document?`（任意参照・非所有・nullify）を追加**し、ドキュメント由来のタップ登録を出現元として記録、AI 単語情報生成に抽出テキストを文脈として渡す（`sourceAudio` と同様）。
  - ※ optional 関連の追加だが、埋め込み Codable ではないため軽量マイグレーションで開ける想定。要検証（**[[swiftdata-codable-migration-pitfall]]** の教訓に留意）。
- 削除: `ModelContext.deleteDocument(_:)` を `deleteAudioClip` を範に実装。実ファイル削除＋**全 `WordOccurrence` から id 一致の `sourceDocument` を nullify**（レッスンを辿らない。ライブラリ型で紐付け解除後に出現だけ残る場合があるため）。レッスン削除ではクリップ本体は残す（nullify）。
- `docs/specs/data-model.md` に §4.6 `Document` を追記（§4.5 を範に）し、§1 関連図・§3 `Lesson`（`documents` 行）・データ構造ツリー・`WordOccurrence`（`sourceDocument?`）を更新する。

## 4. backend（Phase 2 詳細）

新エンドポイント `POST /api/document-extract-translate`（`ocr-translate`/`transcribe-translate` と同型）:

- 入力: `{ fileBase64, mediaType (application/pdf | application/vnd.openxmlformats-officedocument.wordprocessingml.document), targetLanguage }`
- バリデーション: `fileBase64` 必須、`mediaType` ホワイトリスト、`targetLanguage` 必須、デコード後 0 バイト拒否、**サイズ上限**（`MAX_AUDIO_BYTES` に倣い `express.json` の 25mb 上限に収まる値を設定。超過は「短い文書に分割」を促す 400）。
- 処理: §2.2 のハイブリッド抽出 → 翻訳。スキャンPDFは `ocrAndTranslate` をページ単位で再利用。
- ログ: 既存 `insertRequestLog` 相当を **`document_requests` テーブル**（新規 or 既存ログ基盤に相乗り）に記録。トークン数・コスト（抽出/OCR＋翻訳の内訳）・レイテンシ・status・errorMessage。管理画面表示は Phase 5。
- 依存追加: `pdf-parse`（PDFテキスト抽出）, `pdf` → 画像化用（例 `pdfjs-dist` + canvas 等、スキャンOCR用）, `mammoth`（DOCX）。導入コストと bundle への影響を確認。
- ファイル本体の保存: 既存 `imagesDir`/`audio` に倣い `data/documents/` に保存（管理画面での参照用。要否は Phase 5 で確定）。

## 5. iOS 取り込み UI（Phase 3 詳細）

- `AddContentTypeView` に4つ目の行「Document」（`systemImage: "doc.text"` 等、`identifier: "addContentDocumentButton"`）を追加。音声と同じく `.fileImporter` を直接提示する。
- `.fileImporter(allowedContentTypes: [.pdf, UTType(filenameExtension: "docx")!], allowsMultipleSelection: true)` を提示。`.docx` の UTType は `org.openxmlformats.wordprocessingml.document`。
- `DocumentFileImporter`（**`AudioFileImporter` を範に取る**）: セキュリティスコープ付きURLを開始/終了し、`Data(contentsOf:)` → `DocumentStorage.save` → `Document` を `pending` で作成・insert（`into lessons:` 引数で紐付け。ライブラリ型なので `[]` も可）。作成したクリップ数を返す。
- `DocumentStorage`（`AudioStorage`/`PhotoStorage` を範に取る）: `Documents/Documents/` へ `UUID.ext` 保存・削除。
- **抽出＋翻訳のトリガー（v1＝手動、将来＝自動に切替可能）**:
  - `DocumentExtractTranslateService`（Remote サービス、`TranscriptionTranslationService` を範に取る）を**独立した1メソッド**として実装: `Document` を受け取り base64 送信 → `processing` → 結果を保存し `completed`/`failed` 遷移。上限超過は送信前に弾く。
  - v1 は **`DocumentDetailView` の手動ボタン**からこのメソッドを呼ぶ（音声と同じ）。
  - **自動化への布石**: 呼び出しは「`Document` を渡すと抽出＋翻訳して状態遷移する」1関数に閉じ込め、`DocumentFileImporter` の取り込み完了直後にも同じ関数を呼べるようにしておく。将来は取り込みフローに1行足すだけで自動化できる（モデル・サービス・エンドポイントは変更不要）。

## 6. iOS 詳細画面 / 管理画面 / テスト

### Phase 4: 詳細画面 `DocumentDetailView`
- `AudioDetailView` を範に、状態分岐表示（pending/processing/failed/completed）。
- **手動ボタン「Extract & Translate」**: `DocumentExtractTranslateService`（§5）を呼ぶ。pending/failed 時に表示（音声詳細と同じ体験）。
- completed 時: 英文を `TappableEnglishText` で表示 → タップで単語帳登録（`sourceDocument` を出現元に）。訳は Markdown 表示。
- 失敗時リトライ、削除（`ModelContext.deleteDocument`: 実ファイル削除＋ `sourceDocument` 参照の nil 化。`deleteAudioClip` を範に）。
- **ライブラリ導線（音声と同型）**: 文書ライブラリ一覧＋レッスン紐付けピッカー（`WordLessonPickerView` / 音声のレッスン紐付けに倣う）。レッスン一覧（`LessonsView`）にも紐付く文書行を出す。既存の音声ライブラリ導線の作りに合わせて実装する。

### Phase 4.5: アプリ内ファイル表示（ビューア）

取り込み時に原本を `Documents/Documents/` に保存済みなので（§5 `DocumentStorage`）、ビューアはそのローカル URL を指すだけでよい。iOS 17 / Swift 6、システムフレームワークは既存 `WKWebView` と同様 `import` で暗黙リンクされる（`project.yml` に frameworks 追記不要）。

調査結果:

| 形式 | 可否 | 手段 |
| --- | --- | --- |
| PDF | ✅ 完全対応・高忠実 | `PDFKit.PDFView`（`UIViewRepresentable`）。スクロール/ズーム/ページ送り/テキスト選択をネイティブ描画 |
| DOCX | ✅ 対応（読み取り専用・忠実度は近似） | `QuickLook`（`QLPreviewController` を `UIViewControllerRepresentable` でラップ、または SwiftUI `.quickLookPreview(URL?)`）。OS 内蔵の Office 変換を使用 |

- `WKWebView` では DOCX を直接描画できない（HTML でないため）ので流用不可。QuickLook は PDF・DOCX を両方扱える。
- **採用（v1）**: PDF は `PDFView` でインライン埋め込み、DOCX は `QuickLook`。追加依存ゼロ。`DocumentDetailView` に「原本を表示」導線（またはタブ/セグメント）を置き、`fileKind` で `PDFView` / `QuickLook` を出し分ける。
  - 実装は `DocumentFileViewer`（`fileKind` で分岐する薄い SwiftUI ラッパー）を1つ用意。`PDFViewer`（`UIViewRepresentable`）と `QuickLookPreview`（`UIViewControllerRepresentable`）を内包。
- **将来拡張**: DOCX の忠実度が不足する場合、backend で DOCX→PDF 変換（LibreOffice headless 等）し、両形式を `PDFView` に統一。
- 抽出前（pending/failed）でも**原本の閲覧は可能**にする（表示は抽出結果に依存しない）。

### Phase 5: 管理画面ログ
- `admin.ts` に document リクエストのコスト内訳（抽出/OCR＋翻訳）ページ or 既存ログへの統合表示を追加。仕様書 5.2 の表示内容に「文書と抽出結果の対応」を加える。

### Phase 6: テスト
- Unit: `DocumentStorage`（保存/削除）, `DocumentExtractTranslateService`（成功/失敗/上限）, テキスト層判定ロジック, `deleteDocument` の参照 nil 化。
- backend: 抽出（pdf テキスト層あり/なし、docx）と翻訳、サイズ上限、エラーログ。
- UI テスト: `LessonDocumentAddUITests`（追加シート→ファイル選択→一覧反映、`LessonWordAddUITests`/`LessonYouTubeAddUITests` を範に）。

## 7. 影響範囲

- iOS: `AddContentTypeView`（行追加）, 新規 `Document`(model)/`DocumentStorage`/`DocumentFileImporter`/`DocumentExtractTranslateService`/`DocumentDetailView`/`DocumentFileViewer`(+`PDFViewer`/`QuickLookPreview`), `WordOccurrence`(+`sourceDocument?`), 全 `ModelContainer` 登録, `DebugDataCleaner`, `LessonsView`（一覧導線）。frameworks は `import`（PDFKit / QuickLook）のみで暗黙リンク（`project.yml` 変更不要）。
- backend: `index.ts`（新エンドポイント）, 新規 `documentExtract.ts`（抽出）, `db.ts`（ログテーブル）, `admin.ts`（表示）, `package.json`（依存追加）。
- docs: `data-model.md`（§4.6 Document）, `app-spec.md`（3.6 ドキュメント取り込み節）。

## 8. テスト方針

各 Phase 完了時に該当 unit / UI テストを追加・green を確認。backend はサンプル PDF（テキスト層あり/スキャン）・DOCX を fixture に置いて抽出をテスト。実機/シミュレータで「ファイル」ピッカーからの取り込み→翻訳→単語登録の一連を手動確認。

## 9. 決定済み事項 / 残課題

### 決定済み（ユーザー確認済み）
- **対象形式**: PDF + DOCX（`.doc` 対象外）
- **テキスト処理**: ハイブリッド（抽出優先＋スキャン時OCRフォールバック）
- **抽出＋翻訳トリガー**: v1 手動ボタン、独立サービス化して将来自動化可能に
- **所属単位**: ライブラリ型（`AudioClip` 同型・多対多・nullify）
- **DOCX 表示**: QuickLook で v1 十分（backend DOCX→PDF 変換は将来拡張）

### 実装時に詰める技術課題（着手可能・実装内で解決）
1. 長尺・多ページ文書の分割・コスト上限方針（v1 は単一ドキュメント一括、上限超過は送信前に弾く）。
2. `WordOccurrence.sourceDocument?` / `Lesson.documents` 追加時のマイグレーション検証（**[[swiftdata-codable-migration-pitfall]]** の storage+computed 方式を `processingStatus` に適用済み。関連追加自体の軽量マイグレーション可否を実機確認）。
3. backend の PDF テキスト抽出・PDF 画像化（スキャンOCR用）・DOCX 抽出ライブラリの選定と依存サイズ（`pdf-parse` / `pdfjs-dist`+canvas / `mammoth` 等の候補を Phase 2 冒頭で確定）。

## 10. Phase 一覧（TODO 子タスク対応）

- [ ] Phase 1: `Document` データモデル追加（+ ModelContainer 登録 / DebugDataCleaner / data-model.md）
- [ ] Phase 2: backend 抽出＋翻訳エンドポイント（PDF/DOCX＋スキャンOCRフォールバック＋コストログ）
- [ ] Phase 3: iOS 取り込み UI（AddContentTypeView 追加 / DocumentFileImporter / Storage / Remote サービス）
- [ ] Phase 4: iOS 詳細画面 DocumentDetailView（英文タップ登録 / 訳表示 / 削除 / 一覧導線）
- [ ] Phase 4.5: アプリ内ファイル表示（PDF=PDFView / DOCX=QuickLook の `DocumentFileViewer`）
- [ ] Phase 5: 管理画面ログ表示
- [ ] Phase 6: テスト（unit / backend / UI）
