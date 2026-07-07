# 既存単語の登録を「Add Word」フォームで弾く

## 目的・背景

`WordAddView`（手動の Add Word フォーム）で既に登録済みの単語を入力しても、現状は
`WordRegistrar.register` が同綴り既存 Word を黙って再利用し、何のフィードバックもなく
シートが閉じる。ユーザーは「登録できた」と誤認しやすい。

そこで入力中に重複を検知し、**説明文を表示して Add ボタンを無効化（＝アプリ側ではじく）** する。

対象は手動フォームのみ。英文タップ登録（`WordRegistrationModifier`）は既に
「既存語 → 詳細へ遷移 / "Already added" トースト」で重複を扱えているため変更しない。

## 対応方針

`WordAddView` に、入力テキストと選択レッスンから重複状態を導出する computed を追加する。

- 実効レッスン `effectiveLesson = fixedLesson ?? Picker選択レッスン`（`addWord()` と同じ導出を共通化）
- 重複判定:
  - 同綴り（case-insensitive、`WordRegistrar` と同じ述語）の既存 Word が無ければ重複ではない
  - 既存 Word がある場合:
    - 実効レッスンが無い（グローバル一覧への追加）→ **純粋な重複** → はじく
      - メッセージ: `“<word>” is already in your word list.`
    - 実効レッスンがあり、その単語が**既にそのレッスンに出現している**（`occurrences` に
      `lesson.id` 一致あり。レッスン単語一覧の dedup と同じ word 単位判定）→ **純粋な重複** → はじく
      - メッセージ: `“<word>” is already in this lesson.`
    - 実効レッスンがあり、まだそのレッスンに紐付いていない → **新規リンクが生じる** → 許可
      （既存 Word を新レッスンに紐付ける有用な操作。ユーザー選択 Q2 に従う）

はじく＝
- 第1セクションの footer を、通常の AI 説明文から**警告ラベル**（`exclamationmark.triangle.fill` +
  orange。既存 `WordRow` の警告色と統一）に差し替える
- Add ボタンを `disabled(trimmedText.isEmpty || isDuplicate)` にする

テキスト・Picker の変更に反応してリアルタイムに切り替わる（例: 既存語を打って None なら弾かれ、
未紐付けレッスンを選ぶと警告が消えて Add が有効化される）。

## 影響範囲

- `ios/ESLLearningAssistant/Sources/Views/WordAddView.swift` のみ変更（ロジックは view 内に閉じる）
- `WordRegistrar` は無変更（重複時は Add が押せないため register は呼ばれない）
- UI テスト追加: `ios/ESLLearningAssistantUITests/WordAddDuplicateUITests.swift`

## テスト方針

- UI テスト（新規）:
  1. 単語 "apple" を追加
  2. 再度 Add Word を開き "apple" を入力 → 警告文が表示され Add が無効
  3. 大文字小文字違い "Apple" でも同様に弾かれる（case-insensitive）
- 既存 UI テスト回帰:
  - `LessonWordAddUITests`（fixedLesson で新規語 "greeting" を追加）は影響なし
- シミュレータビルドでコンパイル確認

## Phase / Step

- [x] Step 1: `WordAddView` に重複検知・警告・Add 無効化を実装
- [x] Step 2: 重複はじきの UI テストを追加
- [x] Step 3: ビルド／テストで検証（`WordAddDuplicateUITests` 追加・`LessonWordAddUITests` 回帰なし）
