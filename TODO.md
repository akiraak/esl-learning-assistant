# TODO

## 管理画面

- [ ] 文字起こし音声（`audio/aac`）の長さがブラウザ上で実測の約 2 倍に見える
      本番 `/admin/transcriptions` の 30 件中 17 件が iOS から届く ADTS AAC（`audio/x-aac`）で、
      ヘッダにフレーム数を持たないためブラウザ・ffprobe とも `ファイルサイズ ÷ 推定ビットレート` で
      長さを見積もる。実測すると 2 倍ずれる（例: #30 は表示 8:25 に対し実際は 4:14。
      `ffprobe` の推定 504.96 秒 / 全デコードで 253.5 秒、11886 フレーム × 1024 / 48000Hz）。
      このためシークバーの右半分が実体の無い区間になり、中盤以降へ飛ばすと終端扱いになる。
      **ドックプレイヤー導入前の `<audio controls>` でも同じ**（素の `<audio>` で再現確認済み）なので
      今回の変更が原因ではないが、シークを実用にするには対処が要る。
      候補: 取り込み時に m4a へ remux して正しい長さを持たせる /
      サーバ側で実長を測って DB に持ち一覧・プレイヤーに渡す。

## 片付け

- [ ] iOS に残っている添削（Review）の残骸を消す
  - `ios/ESLLearningAssistant/Sources/Models/Composition.swift` の `WritingFeedback` /
    `CompositionRound` / `Composition.feedback` / `latestFeedback`。
    バックエンドの `/api/writing-feedback`・`writingFeedback.ts` は 2026-08-02 に削除済みで、
    iOS 側も参照している View / Service はもう無い（SwiftData のスキーマだけが残っている）。
    消すとマイグレーションが要るかを確認してから。
