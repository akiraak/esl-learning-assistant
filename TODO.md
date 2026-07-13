# TODO

- [ ] 音声ファイルを読み込むときに音量のノーマライズを行う [plan](docs/plans/audio-import-volume-normalization.md)
  - [ ] Phase 1: AudioNormalizer（2パス分析＋ゲイン適用＋AAC書き出し）とユニットテスト
  - [ ] Phase 2: AudioFileImporter への組み込み（async化・normalize:パラメータ・失敗時フォールバック）と取り込み中UI
  - [ ] Phase 2.5: 正規化ON/OFFチェックボックス（AudioImportLessonViewにToggle＋@AppStorage、AddContentTypeViewもシート経由に）
  - [ ] Phase 3: シミュレータ/実機での動作確認と後片付け