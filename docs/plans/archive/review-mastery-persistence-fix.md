# 復習クイズの masteryPercent が永続化されないバグの修正

## 目的・背景

単語クイズで正解しても、セッション終了後に単語詳細を見ると Mastery が 0% のままでクリアできない。

調査の結果、`WordReviewState` の `stepIndexStorage` / `correctCountStorage` / `lapseCountStorage` / `masteryPercentStorage` の4フィールドが **SwiftData ストアを経由すると一切永続化されていない** ことを再現テストで確認した（`reviewCount` などプロパティ名とキー名が一致するフィールドは永続化される）。

原因: SwiftData は埋め込み Codable を実プロパティ名ベースで管理するが、CodingKeys で
`masteryPercentStorage` → `"masteryPercent"` のようにリネームしていたため、読み書きのキーがカラムと一致せず値が黙って捨てられていた。

- masteryPercent: 解答のたびに保存されるが読み戻すと常に 0 → 何回正解しても 100% に到達せずクリア不能（セッション内は同一インスタンスのため見かけ上進む）
- stepIndex / correctCount / lapseCount: 導入時から同じ理由で永続化されていなかった（Step・Accuracy 表示も実は常に初期値）

## 対応方針

1. `WordReviewState` の CodingKeys のリネームをやめ、キー名を実プロパティ名（`stepIndexStorage` 等）に揃える
   - WordReviewState を JSON で保存している箇所は他になく（SwiftData のみ）、旧キー名で保存されたデータはそもそも存在しない（保存自体が失敗していた）ため互換問題はない
   - ストレージをオプショナルにして computed で 0 を既定値にするパターンは維持する（非オプショナル追加はマイグレーション失敗の地雷。docs 参照）
2. 再現テスト（ストア経由のラウンドトリップ）を回帰テストとして残す
3. 既存の `WordReviewStateTests` のレガシーJSONテストを新キー名の実態に合わせて更新する

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Models/Word.swift`（CodingKeys / init(from:) のみ。スキーマは nullable カラム追加のライトウェイトマイグレーションで対応可能）
- 既存ユーザーのデータ: 該当4フィールドは今まで常に NULL だったため、修正後も 0 スタートで実害なし

## テスト方針

- 新規: `WordReviewStatePersistenceTests` — オンディスクストアに保存→コンテナ再オープンで masteryPercent / correctCount 等が読み戻せること
- 既存: `WordReviewStateTests` / `ReviewSchedulerTests` を含むユニットテスト全体を実行
