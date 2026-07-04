# WordReviewState 追加フィールドによるマイグレーション失敗の修正

## 目的・背景

実機 (iPhone 14 Pro) で「クラスを作成しても表示されない」バグが報告された。調査の結果、原因はクラス作成処理ではなく、**SwiftData ストアのマイグレーション失敗でストア自体が開けなくなっている**ことだった。

- 復習クイズ Phase 2 (`f8c7f06`) で `WordReviewState`（`Word.reviewState` に埋め込んだ Codable 構造体）に `stepIndex` / `correctCount` / `lapseCount` を**非オプショナル**で追加した
- SwiftData は埋め込み Codable を JSON ではなく個別カラム (`ZSTEPINDEX` 等) に展開して保存するため、`init(from:)` の `decodeIfPresent` によるフォールバックはマイグレーション時に使われない
- 既存の Word 行を持つストア（実機）ではライトウェイトマイグレーションが
  `Cannot migrate store in-place: Validation error missing attribute values on mandatory destination attribute (entity=Word, attribute=stepIndex)`
  で失敗し、**Store failed to load** となる
- `.modelContainer(for:)` は読み込み失敗を無言で握りつぶすため、アプリは「データゼロ」の空状態で動き続け、作成操作も `try? modelContext.save()` が無言で失敗する

再現方法: 実機のストア（旧スキーマ + Word 行あり）をシミュレータのアプリコンテナにコピーして現行ビルドを起動する（調査時に iPhone 17 Pro シミュレータへ配置済み）。

## 対応方針

### Phase 1: WordReviewState をマイグレーション可能にする

- `stepIndex` / `correctCount` / `lapseCount` の**ストレージをオプショナル** (`Int?`) の private プロパティにし、公開 API は従来どおり非オプショナルの computed プロパティ（`?? 0`）で提供する
- `CodingKeys` で旧キー名 (`stepIndex` 等) を維持し、既存データとの互換を保つ
- カラムが nullable になるため、既存行に値が無くてもライトウェイトマイグレーションが成功する

### Phase 2: エラーの可視化（再発防止）

- `ESLLearningAssistantApp` で `ModelContainer` を明示的に生成し、失敗時は専用のエラー画面を表示する（無言でデータゼロにしない）
- `try? modelContext.save()`（11箇所）を `ModelContext.saveOrLog()` 拡張に置き換え、失敗を os.Logger で記録し debug ビルドでは assertionFailure で即座に気付けるようにする

### Phase 3: 検証

- ユニットテスト（WordReviewStateTests / ReviewSchedulerTests ほか）を実行
- 旧スキーマの実機ストアコピーを配置したシミュレータで新ビルドを起動し、
  1. マイグレーションが成功しクラス「Shoreline Lv4」「Test Class」が表示されること
  2. クラス作成が一覧に即時反映され、再起動後も残ること
  を確認する
- 既存 UI テスト（クラス作成フロー）を実行する

## 影響範囲

- `ios/.../Models/Word.swift`（WordReviewState）
- `ios/.../Support/ReviewScheduler.swift`・`Views/WordDetailView.swift`（アクセスは computed プロパティ経由のため原則変更不要）
- `ios/.../ESLLearningAssistantApp.swift`（コンテナ生成とエラー画面）
- `try? modelContext.save()` を使う 11 ファイル

## テスト方針

上記 Phase 3 のとおり。実機データはマイグレーション失敗時に変更されないため喪失なし。修正版を実機にインストールすれば既存データがそのまま利用可能になる見込み。
