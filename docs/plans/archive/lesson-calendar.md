# レッスンをカレンダーに置き換える

## 目的・背景

現状のレッスンは「クラス内の手動作成・手動命名の単位」で、日付の概念を持たない
（`Lesson` の日付は `createdAt` のみ。並び順・既定選択もすべて `createdAt` ベース）。
実際の使われ方は「その日の授業 = 1レッスン」なので、レッスンを**クラスのカレンダー上の日付**に
紐づく単位へ置き換え、選択・作成をカレンダー UI から行えるようにする。

要件（TODO.md より）:

- クラスにはレッスンの日付が関連づけられる
- 既存のレッスンはクラスカレンダーの日付に紐づく
- クラスに同日のレッスンはない（クラス内で日付が一意）
- レッスンの選択や作成はカレンダーのインターフェースから行う

Lesson/Class は SwiftData の端末内ローカル保存のみで backend は関与しない
（[data-model.md](../specs/data-model.md) §0）。iOS 側のみの変更で完結する。

## 対応方針

### Phase 1: データモデルと既存データの移行

1. **`Lesson` に授業日を追加** — `ios/ESLLearningAssistant/Sources/Models/Lesson.swift`
   - `AudioClip.processingStatus` 等と同じ **optional storage + computed 方式**で追加する
     （非オプショナル追加はストアが開けなくなるため厳禁。[data-model.md](../specs/data-model.md) §4.6 注記と同方針）
     ```swift
     var dateStorage: Date?                     // 実ストレージ（NULL 許容）
     var date: Date {                           // 公開 API
         get { dateStorage ?? Calendar.current.startOfDay(for: createdAt) }
         set { dateStorage = Calendar.current.startOfDay(for: newValue) }
     }
     ```
   - 保存値はローカル Calendar の `startOfDay` に正規化する。ただし同日判定は保存値の
     直接比較ではなく常に `Calendar.current.isDate(_:inSameDayAs:)` で行う
     （タイムゾーン変更などによる保存値の微妙なズレに頑健にするため）
2. **既存レッスンのバックフィル移行（1回限り）**
   - アプリ起動時に UserDefaults フラグ `lessonDateBackfillV1` で1回だけ実行
     （過去の `ttsPlainTextRekeyV1` と同パターン）
   - 全 `Lesson` の `dateStorage` を `createdAt` の日付で明示的に埋める
   - **同一クラス内で同日衝突した場合**: `createdAt` 昇順で最初の1件がその日を取り、
     以降の衝突レッスンは「次の空いている日」へ順送りする（データを消さない・決定的）
3. **表示名のフォールバック** — `Lesson.displayTitle`（computed）を追加:
   `title` が非空ならそれ、空なら日付の書式表示（例: `2026/7/10 (金)`）。
   title 表示箇所（`LessonsView` の switcherCard、単語詳細の登場レッスン等）を
   grep で洗い出して `displayTitle` に置換する
4. **クラス内で日付一意のガード関数** — `Class.lesson(on: Date) -> Lesson?` を追加し、
   作成時の防御チェックにも UI の出し分けにも使う

### Phase 2: カレンダー UI（選択・作成）

1. **`LessonCalendarView` 新設** — `UICalendarView` の `UIViewRepresentable` ラッパー
   - iOS 17 ターゲットなので利用可（月表示・スワイプでの月移動・ローカライズが標準で付く）
   - `decorationView`（ドット等）でレッスンのある日をマーク、現在レッスンの日は強調表示
   - 単一日付選択（`UICalendarSelectionSingleDate`）。過去・未来とも選択可
     （未来日のレッスン作成 = 予定作成として許容する）
2. **`ClassLessonSwitcherView` をカレンダーベースに再構成**
   - 現状の「クラス Section × レッスン行リスト」を廃止し、
     **上部: クラス切り替え（Menu or Picker、＋クラス追加/編集導線は維持）／
     下部: 選択中クラスのカレンダー** の構成にする
   - **レッスンのある日をタップ** → そのレッスンを選択（AppStorage 更新）して dismiss
   - **レッスンのない日をタップ** → 確認ダイアログ「YYYY/M/d のレッスンを作成」→
     作成（`title = ""`）・選択して dismiss。タイトル入力は求めない
     （日付が識別子になるため。名前を付けたい場合は後から Rename）
   - 作成直前に `Class.lesson(on:)` で防御チェック（存在すれば作成せず選択に切り替え）
3. **`LessonAddView` を廃止**（作成はカレンダー経由に一本化）。
   `ClassAddView` / `ClassEditView` は現状維持
4. **`LessonEditView` の調整**
   - タイトルの同名重複チェックを撤廃（一意性は「クラス内で日付一意」に移る。空タイトルも許容）
   - 導線: レッスン行が消えるため、`LessonsView` の switcherCard のコンテキストメニュー
     （または詳細画面のツールバー）から開けるようにする
   - （任意・後回し可）日付の変更 UI: 空いている日のみ選択可の DatePicker。
     v1 スコープ外にしてもよい

### Phase 3: 並び順・既定選択の切り替えと後片付け

1. **`createdAt` 参照を `date` へ切り替え**
   - `LessonsView.currentLesson` の既定選択（`createdAt` 最大 → `date` 最大）
   - レッスンの並び・比較箇所を grep で洗い出し、`date` ベースへ統一
     （クラスの並びは従来どおり `createdAt` のまま）
2. **仕様書の更新**
   - [data-model.md](../specs/data-model.md) §3 Lesson: `dateStorage`/`date` 追加、
     「クラス内で日付一意」「title は任意ラベル」への変更を反映
   - [screen-design.md](../specs/screen-design.md) §2.2: 切り替えシートを
     カレンダー構成に差し替え
3. TODO.md の親タスクを DONE.md へ移動し、本プランを `docs/plans/archive/` へ移す

## 影響範囲

- 変更: `ios/ESLLearningAssistant/Sources/Models/Lesson.swift`（date 追加）
- 変更: `ios/ESLLearningAssistant/Sources/Models/Class.swift`（`lesson(on:)` ヘルパー）
- 新規: `LessonCalendarView.swift`（UICalendarView ラッパー）、
  バックフィル移行コード（App 起動時。`ESLLearningAssistantApp.swift` から呼ぶ）
- 変更: `ClassLessonSwitcherView.swift`（カレンダーベースへ再構成）、
  `LessonsView.swift`（既定選択・switcherCard 表示・編集導線）、
  `LessonEditView.swift`（重複チェック撤廃）
- 削除: `LessonAddView.swift`
- 変更: title 表示箇所の `displayTitle` 置換（grep で確定）
- 変更: `docs/specs/data-model.md`、`docs/specs/screen-design.md`
- backend・他タブ（単語/Audio/Docs のデータ構造）への変更なし
- **XcodeGen 管理**のため、ファイル追加/削除後は `xcodegen generate` を実行

## テスト方針

- `xcodebuild` でビルド確認
- **マイグレーション確認**（最重要）: 既存データ入りのシミュレータで新ビルドを起動し、
  - ストアが開ける（optional 追加のみでライトウェイト移行が通る）こと
  - 全レッスンに日付が付き、選択中レッスンが維持されること
  - 同一クラス・同日 `createdAt` のレッスンを事前に用意し、衝突が順送りで解消されること
  - 2回目起動でバックフィルが再実行されないこと
- シミュレータでの GUI 確認（cliclick + simctl screenshot）:
  - カレンダーにレッスンのある日がドット表示される
  - レッスンのある日タップ → 選択されて Lessons 画面に反映される
  - 空き日タップ → 確認 → 作成・選択される。同じ日をもう一度タップすると選択になる
  - クラスを切り替えるとカレンダーのドットがそのクラスのものに変わる
  - タイトル未設定レッスンが日付表示（displayTitle）で見える
  - Rename 導線から従来どおりタイトル編集できる
- 実機ビルド（`run-ios-device.sh`）で軽く動作確認
