# クイズ生成: 音声不要形式への audioText 混入の除去

## 目的・背景

音声を使わないクイズ形式（needsAudioText=false の tc2〜tc7・tt1）に、AI が余計に返した
audioText（displayText のコピー等）が `validateAndConvert` で除去されずそのまま保存されている。

- 発見: 2026-07-11 の熟語対応 Phase 3 作業中。フレーズ固有ではなく既存単語でも発生
- ローカル DB の実測: tc3 24件中20件・tc6 18件中14件・tt1 24件中10件に混入
- 影響:
  - `pregenerateQuizAudio`（ttsStore.ts）が混入分まで TTS プリ合成 → 無駄な API コスト
  - iOS は audioText 非 null を音声問題として扱うため、不要な Play Audio ボタン表示・
    音声ダウンロード・DL 失敗時の出題除外が起きる（ReviewSessionView.swift）
  - tc3 では空所付き文がそのまま audioText に入っており、再生すると "_____" を読み上げる

## 対応方針

1. **生成側（再発防止）**: `validateAndConvert`（backend/src/quizQuestions.ts）で
   `needsAudioText=false` の形式は audioText を捨てて null で保存する（choices / typing 両分岐）
2. **保存済みデータ（掃除）**: db.ts の起動時クリーンアップに冪等な UPDATE を追加する
   （既存の tt2 / 廃止12形式 DELETE と同じパターン）

   ```sql
   UPDATE quiz_questions
   SET question_json = json_set(question_json, '$.audioText', null)
   WHERE format IN ('tc2','tc3','tc4','tc5','tc6','tc7','tt1')
     AND json_extract(question_json, '$.audioText') IS NOT NULL
   ```

3. **TTS キャッシュ（対象外）**: 混入分の合成済み音声（tts_audio）は、正規用途（例文読み上げ等）と
   共有されうるキー（sha256(model|text)）のため個別削除はしない。既存の保持ポリシーに任せる

## 影響範囲

- backend/src/quizQuestions.ts: validateAndConvert（+ テスト用に export）
- backend/src/db.ts: 起動時クリーンアップ追加
- iOS 側の変更なし（audioText=null は既存の非音声形式と同じ扱い）

## テスト方針

- backend/test/quizQuestions.test.ts に validateAndConvert のユニットテストを追加
  - 非音声形式（tc3/tt1）: 混入 audioText が null になる（choices / typing 両分岐）
  - 音声形式（vc1）: audioText は従来どおり保持される
  - 音声形式で audioText 欠落: 従来どおり variant ごと棄却（回帰ガード）
- DB クリーンアップはローカル DB で起動前後の混入件数を SQL で確認する
