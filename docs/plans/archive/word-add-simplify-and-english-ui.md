# 単語追加ダイアログの簡素化＋UI表記の全英語化

## 目的・背景

- 単語登録時にAIが訳語・例文・品詞などを自動生成するようになったため（word-ai-info-generation）、
  単語追加ダイアログの手入力フィールド（訳語・例文・品詞）は冗長になった。
  **見出し語＋レッスン選択だけ**のシンプルな登録に変更する。
- タブバーは英語化済み（Lessons / Words / Settings）だが画面内の文言は日本語のまま。
  **UI表記（ユーザーに見える文字列）を全て英語に統一**する。
  - AI生成コンテンツ（訳語・例文の母語訳など）はデータであり対象外（母語=日本語のまま）
  - コードコメントは日本語のまま（プロジェクト慣習）

## 対応方針

### Phase 1: 単語追加ダイアログの簡素化

- `WordAddView`: 訳語・例文・品詞の入力フィールドを削除し、見出し語＋レッスンPickerのみにする
  - 見出し語フィールドに `accessibilityIdentifier("wordTextField")` を付与（UIテストの
    プレースホルダー文字列依存を解消）
  - `Word` は `translation: ""` で作成（登録ボタンの有効条件は見出し語のみ）
- `WordAIInfoGenerator`: 生成成功時に `word.translation` が空なら
  `senses[0].meaning`（文脈に合う語義の母語訳）で自動補完する
- `WordRow` / `WordDetailView`: `translation` が空の間は表示しない（空行・空セクション防止）

### Phase 2: UI表記の英語化

対象ファイル（ユーザー可視文字列のみ変更）:

- `ContentView`（変更なし・英語済み）
- `LessonsView` / `ClassLessonSwitcherView` / `ClassAddView` / `LessonAddView`
- `CaptureView` / `PhotoDetailView`
- `WordsView` / `WordAddView` / `WordDetailView`
- `SettingsView`（デバッグメニュー含む）

主な対訳: 追加→Add、キャンセル→Cancel、閉じる→Close、削除する→Delete、
訳語→Translation、語義→Meanings、発音→Pronunciation、語形変化→Word Forms、
例文→Examples、よく使う組み合わせ→Collocations、類義語・反意語→Synonyms & Antonyms、
学習メモ→Study Notes、登場したレッスン→Appears in Lessons、
声のタイプ ちょビ/なるこ→Chobi/Naruko（固有名詞はローマ字化）など。

### Phase 3: テスト追随・確認

- UIテストの日本語文字列参照（"追加"・"写真を追加"・"OCR結果（英語）"・重複レッスン
  メッセージ・デバッグメニュー・生成失敗ラベル等）を英語に更新
- `testWordAddFlow` から訳語入力手順を削除
- ユニットテスト・UIテストの実行、シミュレータでの表示確認

## 影響範囲

- iOS Views 全般（上記）、`WordAIInfoGenerator`（translation自動補完）
- バックエンド・SwiftDataモデル構造の変更なし（`Word.translation` は空文字で作成されるのみ）
- UIテスト（文字列参照の英語化）

## テスト方針

- ユニットテスト: 生成成功時の translation 自動補完（空のとき補完・入力済みのとき温存）
- UIテスト: 新しい単語追加フロー（見出し語＋レッスンのみ）、英語ラベルでの既存フロー
- シミュレータのスクリーンショットで英語表記を目視確認
