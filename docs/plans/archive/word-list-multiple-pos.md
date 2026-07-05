# 単語一覧の訳表示に複数品詞を反映する

## 目的・背景

単語一覧（`WordsView` の `WordRow`）は `word.translation` を訳語として表示している。
`translation` は AI 生成完了時に**先頭語義（文脈に合う語義）の意味だけ**で自動補完されるため、
`book`（名詞「本」/ 動詞「予約する」）のように複数の品詞にまたがる語義を持つ単語でも、
一覧では 1 つの意味しか見えない。

複数品詞を持つ単語であることを一覧の訳表示でも把握できるようにする。

## 対応方針

- `Word` に一覧表示用の派生プロパティ `listTranslation` を追加する。
  - `aiInfo.senses` を走査し、先頭語義の品詞と異なる品詞が存在する場合、
    各品詞グループの代表的な意味（そのグループ最初の語義の meaning）を「 / 」で連結する。
  - 先頭は `word.translation`（ユーザー編集済みの訳語を尊重）を使い、
    それ以外の品詞の意味を後ろに追記する。ユーザー編集を破壊しない。
  - `aiInfo` が無い・訳語が空の場合は `translation` をそのまま返す（従来通り）。
  - 例: `book` → `本 / 予約する`
- `WordRow` の表示を `word.translation` → `word.listTranslation` に差し替える。
  - 表示形式は「意味を『/』区切り」（ユーザー確認済み）。`lineLimit(1)` は維持。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Models/Word.swift`（`listTranslation` 追加）
- `ios/ESLLearningAssistant/Sources/Views/WordsView.swift`（`WordRow` の表示差し替え）
- 単語詳細（`WordDetailView`）は Meanings セクションで各語義を既に個別表示しているため変更なし。

## テスト方針

- `Word.listTranslation` の単体テストを追加する。
  - 単一品詞 → `translation` のまま
  - 複数品詞 → 「 / 」連結（先頭は translation、以降は他品詞の代表意味）
  - 同一品詞の複数語義 → 連結せず `translation` のまま
  - `aiInfo` 無し / 訳語空 → `translation` のまま
