import { config } from "./config";
import { callStructured } from "./ocrTranslate";

// 入力語を辞書見出し語（lemma）へ正規化した結果。iOS 側 WordNormalization（Sources/Models）と同構造。
// フィールドを増減する場合は両方を合わせること。
//
// status で確認UIの出し分けを決める（詳細は docs/plans/word-input-normalization.md）:
//   canonical    既に見出し語 → lemma は入力と同じ / 確認UIを出さず即登録
//   inflected    語形変化（過去形/複数形/比較級等）→ lemma は原形 / 確認UIを出す
//                フレーズの変化形（looked up 等）もここに含める（docs/plans/word-phrase-support.md）
//   misspelled   綴り間違い → lemma は正しい綴りの原形（例 writed→write）/ 確認UIを出す
//                フレーズ内の綴り間違いもここに含める
//   proper_noun  固有名詞（人名等）→ 訂正しない（lemma は入力と同じ）
//   phrase       既に辞書見出しの基本形である複数語の連語（句動詞・イディオム等）→ lemma は入力と同じ
//   phrase_part  文脈付き呼び出しで、タップ語が文中の複数語表現（句動詞・イディオム）の一部
//                → lemma は表現全体の辞書基本形（例: "up" in "I looked it up." → "look up"）/ 確認UIを出す
//   unknown      判定不能・英語でない・明らかな文 → lemma は入力と同じ
export const WORD_NORMALIZE_STATUSES = [
  "canonical",
  "inflected",
  "misspelled",
  "proper_noun",
  "phrase",
  "phrase_part",
  "unknown",
] as const;

export type WordNormalizeStatus = (typeof WORD_NORMALIZE_STATUSES)[number];

const WORD_NORMALIZE_SCHEMA = {
  type: "object",
  properties: {
    status: {
      type: "string",
      enum: [...WORD_NORMALIZE_STATUSES],
      description:
        "入力語の分類。" +
        "canonical=既に辞書見出し語（原形・正しい綴り）。" +
        "inflected=正しく綴られた語形変化（過去形・過去分詞・三単現・複数形・比較級・最上級・-ing形など）。" +
        "複数語フレーズの変化形（例:『looked up』『takes care of』）もここに含める。" +
        "misspelled=綴り間違い。変化形の綴り間違い（例:『writed』『runned』）や、" +
        "フレーズ内の綴り間違いもここに含める。" +
        "proper_noun=固有名詞（人名・地名・商品名など。訂正しない）。" +
        "phrase=空白を含む複数語の連語（句動詞・イディオム・コロケーション）で、既に辞書見出しの基本形のもの。" +
        "変化形や綴り間違いを含むフレーズは phrase ではなく inflected / misspelled とする。" +
        "phrase_part=文脈の文が与えられ、かつ入力語がその文中で複数語表現（句動詞・イディオム）の" +
        "一部として使われている場合。文脈が無い呼び出しでは使わない。" +
        "unknown=英単語として判定できない・英語でない・明らかな文。" +
        "inflected / misspelled は lemma が入力と異なる（＝訂正がある）場合のみ使う。" +
        "入力が既に基本形なら、単語は canonical、フレーズは phrase とする。",
    },
    lemma: {
      type: "string",
      description:
        "登録すべき辞書見出し語。inflected/misspelled では常に『原形（基本形）』にする。" +
        "語形変化していれば原形に戻し、綴り間違いは正しい綴りに直す。両方に該当する場合" +
        "（＝原形でない語の綴り間違い）は、綴りを直したうえでさらに原形へ戻す。" +
        "例:『writed』→『write』（過去形 wrote の綴り間違いだが、登録するのは原形 write）。" +
        "複数語フレーズも同様に辞書見出しの基本形にする（中心となる動詞を原形化。" +
        "例:『looked up』→『look up』、『takes care of』→『take care of』）。" +
        "フレーズの見出しに目的語プレースホルダ（sth / sb など）は付けない。" +
        "『one's』が不可欠な定型（例: make up one's mind）のみ one's を残す。" +
        "phrase_part では、入力語を含む表現全体の辞書基本形にする（分離した目的語・代名詞は除き、" +
        "中心動詞は原形化。例: 文『I looked it up yesterday.』の『up』→『look up』）。" +
        "canonical/proper_noun/phrase/unknown では入力語をそのまま（トリムのみ）返す。小文字化はしない。",
    },
    reason: {
      type: "string",
      description:
        "なぜその lemma に直したかを『母語』（指定された言語コードの言語）で1文で説明する。" +
        "例（inflected）:「『ran』は動詞『run』の過去形です」。" +
        "phrase_part では必ず空でない説明を返す（確認UIの説明文になる。" +
        "例:「文中の『up』は句動詞『look up』の一部です」）。" +
        "canonical/proper_noun/phrase/unknown の場合は空文字列 \"\" を返す（確認UIを出さないため）。",
    },
  },
  required: ["status", "lemma", "reason"],
  additionalProperties: false,
} as const;

export interface WordNormalization {
  status: WordNormalizeStatus;
  lemma: string;
  reason: string;
}

export interface WordNormalizeResult {
  normalization: WordNormalization;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

export async function normalizeWord(
  word: string,
  targetLanguage: string,
  context?: string
): Promise<WordNormalizeResult> {
  // 文脈付き（本文タップ登録）のときだけ熟語判定の指示を足す。文脈なしのプロンプトは従来と同一
  // （手動入力の回帰リスクを避ける。docs/plans/word-phrase-support.md Phase 4）。
  const contextLines = context
    ? [
        `この語は、次の英文の中でタップされました: "${context}"`,
        `まず、タップされた語がこの文の中で複数語表現（句動詞・イディオム・定型コロケーション）の一部として使われているかを判定してください。`,
        `一部として使われている場合は status=phrase_part とし、lemma はその表現全体の辞書基本形にします（分離した目的語・代名詞は除き、中心動詞は原形化。例: 文「I looked it up yesterday.」の「up」→ lemma="look up"、文「She takes care of her brother.」の「care」→ lemma="take care of"）。reason には母語でその説明を必ず書きます（例:「文中の『up』は句動詞『look up』の一部です」）。`,
        `複数語表現の一部ではない場合は、文脈は語義のヒントに留め、タップされた語そのものに以降の通常ルール（canonical / inflected / misspelled 等）を適用してください。`,
      ]
    : [];
  const prompt = [
    `英語学習アプリの語彙リスト登録の前処理として、入力された語 "${word}" を辞書見出し語（lemma）へ正規化してください。`,
    ...contextLines,
    `目的は、過去形・複数形などの語形変化を原形に、綴り間違いを正しい綴りに直して、正しい見出し語で登録することです。`,
    `lemma は常に辞書の原形（基本形）にしてください。綴り間違いを直した結果が変化形になる場合は、そこで止めずにさらに原形へ戻します（例:「writed」は過去形 wrote の綴り間違いですが、登録するのは原形「write」。この場合 status は misspelled）。`,
    `入力は "look up" のような複数語のフレーズ（句動詞・イディオム・コロケーション）の場合があります。フレーズも単語と同じルールで、lemma は辞書見出しの基本形にしてください（中心となる動詞を原形化。例:「looked up」→「look up」（status は inflected）、「takes care of」→「take care of」（status は inflected））。`,
    `status の inflected / misspelled は「lemma が入力と異なる＝訂正がある」場合だけ使います。入力が既に辞書見出しの基本形なら訂正は無いので、単語なら canonical、フレーズなら phrase にして reason は空文字列にします（例: 入力「look up」→ status=phrase, lemma="look up", reason=""）。`,
    `フレーズの見出しに目的語プレースホルダ（sth / sb など）は付けません。「one's」が不可欠な定型（例: make up one's mind）のみ one's を残します。`,
    `明らかな文（主語と動詞を備えて文として完結している入力。例:「I looked it up yesterday.」）は語彙の見出しではないため、訂正せず status=unknown で入力どおり返してください。`,
    `reason は言語コード "${targetLanguage}" の言語（母語）で書いてください。原形へ直した理由が伝わるようにしてください。`,
    `固有名詞・英語でない入力は訂正せず、そのまま返してください。`,
  ].join("\n");

  const { json, inputTokens, outputTokens } = await callStructured<WordNormalization>(
    config.wordNormalizeModel,
    WORD_NORMALIZE_SCHEMA,
    [{ type: "text", text: prompt }]
  );

  return {
    normalization: json,
    model: config.wordNormalizeModel,
    inputTokens,
    outputTokens,
  };
}
