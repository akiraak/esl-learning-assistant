import { config } from "./config";
import { callStructured } from "./ocrTranslate";
import type { WordInfo } from "./wordInfo";

// 復習クイズ問題のサーバ生成（docs/plans/archive/quiz-questions-server-storage.md）。
// 1単語 × 1形式につき VARIANTS_PER_FORMAT 件のバリエーションを生成して保存し、
// iOS はその中からランダムに1件を出題する。
// question_json は iOS の ReviewQuestion（ReviewQuestion.swift）と 1:1 対応。

export const VARIANTS_PER_FORMAT = 3;
/// VT2（例文ディクテーション）の単語一致率しきい値（iOS ReviewAnswerJudge と揃える）
export const SENTENCE_MATCH_THRESHOLD = 0.8;

export interface QuizAnswer {
  type: "choices" | "illustrationChoices" | "typing";
  options: string[] | null;
  correctIndex: number | null;
  acceptedAnswers: string[] | null;
  matchRateThreshold: number | null;
}

export interface QuizQuestion {
  format: string;
  instruction: string;
  displayText: string | null;
  audioText: string | null;
  promptIllustrationWord: string | null;
  answer: QuizAnswer;
}

export interface GeneratedQuestion {
  question: QuizQuestion;
  variantIndex: number;
  model: string;
  inputTokens: number;
  outputTokens: number;
}

export interface QuizGenerationResult {
  questions: GeneratedQuestion[];
  /// 全グループ失敗など、部分失敗の内容（成功時は空配列）
  errors: string[];
  totalInputTokens: number;
  totalOutputTokens: number;
}

// -- 品詞・活用形ラベルの日→英マッピング（iOS GrammarLabelMapping.swift と揃える）

const PART_OF_SPEECH_EN: Record<string, string> = {
  名詞: "noun",
  動詞: "verb",
  形容詞: "adjective",
  副詞: "adverb",
  代名詞: "pronoun",
  前置詞: "preposition",
  接続詞: "conjunction",
  冠詞: "article",
  限定詞: "determiner",
  助動詞: "auxiliary verb",
  間投詞: "interjection",
  感動詞: "interjection",
  句動詞: "phrasal verb",
  熟語: "idiom",
  イディオム: "idiom",
};

const POS_CHOICES = ["noun", "verb", "adjective", "adverb"];

const INFLECTION_FORM_EN: Record<string, string> = {
  過去形: "past tense",
  過去分詞: "past participle",
  現在分詞: "present participle",
  進行形: "present participle",
  動名詞: "gerund",
  三人称単数現在: "third-person singular",
  三単現: "third-person singular",
  複数形: "plural",
  比較級: "comparative",
  最上級: "superlative",
  現在形: "present tense",
  原形: "base form",
};

function englishPartOfSpeech(label: string): string | undefined {
  return PART_OF_SPEECH_EN[label.trim()];
}

/// 英語ラベルへ写像できる活用形の一覧 [{formEnglish, text}]
function mappableInflections(info: WordInfo): { formEnglish: string; text: string }[] {
  return info.inflections
    .map((inflection) => ({
      formEnglish: INFLECTION_FORM_EN[inflection.form.trim()],
      text: inflection.text,
    }))
    .filter((entry): entry is { formEnglish: string; text: string } => Boolean(entry.formEnglish && entry.text));
}

// -- 形式定義（AI 生成対象の23形式）

interface FormatSpec {
  id: string;
  answerType: "choices" | "typing";
  needsDisplayText: boolean;
  needsAudioText: boolean;
  /// options[correctIndex]（または acceptedAnswers）が単語そのものであるべき形式の検証用
  correctMustBeWord: boolean;
  /// この単語の素材で出題可能か
  isAvailable: (info: WordInfo) => boolean;
  /// AI への生成指示（1形式分）
  promptSpec: (word: string, info: WordInfo) => string;
}

const hasDefinition = (info: WordInfo) => info.senses.some((s) => s.englishDefinition.trim());
const hasExamples = (info: WordInfo) => info.examples.some((e) => e.english.trim());

const AI_FORMAT_SPECS: FormatSpec[] = [
  {
    id: "tc1",
    answerType: "choices",
    needsDisplayText: true,
    needsAudioText: false,
    correctMustBeWord: true,
    isAvailable: hasDefinition,
    promptSpec: (word) =>
      `tc1: displayText に "${word}" の英語定義（学習者向けに平易な言い換え。バリエーションごとに表現を変える）。` +
      `options は単語4つで正解は "${word}"。誤答は意味の異なる同難易度の実在英単語。`,
  },
  {
    id: "tc2",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: false,
    correctMustBeWord: false,
    isAvailable: hasDefinition,
    promptSpec: (word) =>
      `tc2: instruction は「Which is the correct definition of “${word}”?」。displayText は null。` +
      `options は英語定義4つ。正解は "${word}" の定義、誤答は別の（意味の異なる）単語の定義として自然な文。`,
  },
  {
    id: "tc3",
    answerType: "choices",
    needsDisplayText: true,
    needsAudioText: false,
    correctMustBeWord: false,
    isAvailable: hasExamples,
    promptSpec: (word) =>
      `tc3: "${word}"（または自然ならその活用形）を1箇所だけ "_____" にした英文を displayText に（毎バリエーション別の文を新作）。` +
      `options は空所に入る語4つで、正解は空所にした形そのもの。誤答は文法的に入り得ても意味が通らない語。`,
  },
  {
    id: "tc4",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: false,
    correctMustBeWord: false,
    isAvailable: (info) => info.synonyms.length > 0,
    promptSpec: (word, info) =>
      `tc4: instruction は「Which is closest in meaning to “${word}”?」。` +
      `正解は類義語（候補: ${info.synonyms.join(", ")} から。バリエーションで別の類義語を使ってよい）。` +
      `誤答は意味の遠い同難易度の語（"${word}" の類義語・活用形は誤答に使わない）。`,
  },
  {
    id: "tc5",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: false,
    correctMustBeWord: false,
    isAvailable: (info) => info.antonyms.length > 0,
    promptSpec: (word, info) =>
      `tc5: instruction は「Which is the opposite of “${word}”?」。` +
      `正解は対義語（候補: ${info.antonyms.join(", ")}）。誤答は対義でない語（類義語は良い誤答になる）。`,
  },
  {
    id: "tc6",
    answerType: "choices",
    needsDisplayText: true,
    needsAudioText: false,
    correctMustBeWord: true,
    isAvailable: (info) => info.collocations.length > 0,
    promptSpec: (word, info) =>
      `tc6: コロケーション（候補: ${info.collocations.join(" / ")}）の "${word}" を "_____" にして displayText に。` +
      `options は語4つで正解は "${word}"。誤答はそのコロケーションを成立させない語。`,
  },
  {
    id: "tc7",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: false,
    correctMustBeWord: false,
    isAvailable: (info) => mappableInflections(info).length > 0,
    promptSpec: (word, info) => {
      const forms = mappableInflections(info)
        .map((f) => `${f.formEnglish} = "${f.text}"`)
        .join(", ");
      return (
        `tc7: instruction は「What is the <活用形の英語名> of “${word}”?」（使える活用形: ${forms}。バリエーションで別の形を使ってよい）。` +
        `options は4つで正解は正しい活用形。誤答は規則活用の誤形（例: runed, runned）などの非実在形。`
      );
    },
  },
  {
    id: "tc8",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: false,
    correctMustBeWord: false,
    isAvailable: (info) => {
      const pos = info.senses[0] ? englishPartOfSpeech(info.senses[0].partOfSpeech) : undefined;
      return Boolean(pos && POS_CHOICES.includes(pos));
    },
    promptSpec: (word, info) => {
      const pos = englishPartOfSpeech(info.senses[0].partOfSpeech);
      return (
        `tc8: instruction は「“${word}” is a …」。options は必ず ["noun","verb","adjective","adverb"] の4つ（この順）。` +
        `正解は "${pos}"。3バリエーションとも同一でよい。`
      );
    },
  },
  {
    id: "tc9",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: false,
    correctMustBeWord: true,
    isAvailable: () => true,
    promptSpec: (word) =>
      `tc9: instruction は「Which spelling is correct?」。displayText は null。` +
      `options は綴り4つで正解は "${word}"。誤答は文字入替・脱字・重複によるミススペル（実在語は避ける）。`,
  },
  {
    id: "tc10",
    answerType: "choices",
    needsDisplayText: true,
    needsAudioText: false,
    correctMustBeWord: false,
    isAvailable: (info) => info.senses.length === 1 && hasDefinition(info) && hasExamples(info),
    promptSpec: (word) =>
      `tc10: displayText に "${word}" を含む英文（毎バリエーション新作）。instruction は「What does “${word}” mean in this sentence?」。` +
      `options は英語定義4つで、正解はこの文での "${word}" の意味。誤答は別の単語の定義らしき文。`,
  },
  {
    id: "tt1",
    answerType: "typing",
    needsDisplayText: true,
    needsAudioText: false,
    correctMustBeWord: true,
    isAvailable: hasDefinition,
    promptSpec: (word) =>
      `tt1: displayText に "${word}" の英語定義（tc1 と同様、表現はバリエーションごとに変える）。` +
      `instruction は「Type the word that matches this definition.」。acceptedAnswers は ["${word}"]。`,
  },
  // tt2（例文穴埋め入力）は空所の候補が多すぎて答えを特定できないため廃止
  // （docs/plans/archive/remove-fill-blank-typing.md。4択版の tc3 は存続。
  //   音声で答えを特定できる vtt1 は docs/plans/archive/restore-vtt1.md で復活）
  {
    id: "tt3",
    answerType: "typing",
    needsDisplayText: false,
    needsAudioText: false,
    correctMustBeWord: false,
    isAvailable: (info) => mappableInflections(info).length > 0,
    promptSpec: (word, info) => {
      const forms = mappableInflections(info)
        .map((f) => `${f.formEnglish} = "${f.text}"`)
        .join(", ");
      return (
        `tt3: instruction は「Type the <活用形の英語名> of “${word}”.」（使える活用形: ${forms}）。` +
        `acceptedAnswers は正しい活用形1つ。`
      );
    },
  },
  {
    id: "vc1",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: false,
    isAvailable: hasDefinition,
    promptSpec: (word) =>
      `vc1: audioText は "${word}"（3バリエーションとも）。instruction は「Listen. Which is the correct definition of the word you hear?」。` +
      `options は英語定義4つで正解は "${word}" の定義（表現はバリエーションごとに変える）。`,
  },
  {
    id: "vc2",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: true,
    isAvailable: () => true,
    promptSpec: (word) =>
      `vc2: audioText は "${word}"。instruction は「Listen. Choose the correct spelling.」。` +
      `options は綴り4つで正解は "${word}"、誤答はミススペル（tc9 と同様だが別パターン）。`,
  },
  {
    id: "vc3",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: true,
    isAvailable: hasDefinition,
    promptSpec: (word) =>
      `vc3: audioText に "${word}" の英語定義（読み上げ用に1〜2文で簡潔に）。` +
      `instruction は「Listen to the definition. Which word does it describe?」。options は単語4つで正解は "${word}"。`,
  },
  {
    id: "vc4",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: true,
    isAvailable: hasExamples,
    promptSpec: (word) =>
      `vc4: audioText に "${word}" を含む短い英文（新作、文は画面に表示されない）。` +
      `instruction は「Listen to the sentence. Which word do you hear?」。options は単語4つで正解は "${word}"。` +
      `誤答の単語は audioText の文中に現れないものにする。`,
  },
  {
    id: "vc5",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: true,
    isAvailable: () => true,
    promptSpec: (word) =>
      `vc5: audioText は "${word}"。instruction は「Listen carefully. Which word do you hear?」。` +
      `options は単語4つで正解は "${word}"。誤答は発音が紛らわしい実在語（最小対語や母音違いなど）。`,
  },
  {
    id: "vc6",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: false,
    isAvailable: hasExamples,
    promptSpec: (word) =>
      `vc6: audioText に "${word}" を含む短い英文（新作）。instruction は「Listen. Which sentence do you hear?」。` +
      `options は文4つで、正解は audioText と同一の文。誤答は語順・単語を少し変えた紛らわしい文。`,
  },
  {
    id: "vc7",
    answerType: "choices",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: false,
    isAvailable: (info) => mappableInflections(info).length > 0,
    promptSpec: (word, info) => {
      const forms = mappableInflections(info)
        .map((f) => `${f.formEnglish} = "${f.text}"`)
        .join(", ");
      return (
        `vc7: audioText に "${word}" の活用形1つ（候補: ${forms}）。` +
        `instruction は「Listen. Which form of “${word}” do you hear?」。` +
        `options は活用形の英語名4つ（"past tense" "plural" など）で、正解は audioText の形の名前。`
      );
    },
  },
  {
    id: "vtc1",
    answerType: "choices",
    needsDisplayText: true,
    needsAudioText: true,
    correctMustBeWord: false,
    isAvailable: hasExamples,
    promptSpec: (word) =>
      `vtc1: audioText に "${word}"（または活用形）を含む完全な英文（新作）、displayText にはその文の該当語を "_____" にしたもの。` +
      `instruction は「Listen and choose the word that completes the sentence.」。options は語4つで正解は空所の形。`,
  },
  {
    id: "vtt1",
    answerType: "typing",
    needsDisplayText: true,
    needsAudioText: true,
    correctMustBeWord: false,
    isAvailable: hasExamples,
    // 生成指示は形式グループ（FORMATS_PER_CALL 分割）をまたぐ参照をしない自己完結の文にする
    // （「vtc1 の入力版」のような参照は、別グループに分割された単語で生成漏れを起こした）
    promptSpec: (word) =>
      `vtt1: audioText に "${word}"（または活用形）を含む完全な英文（新作）、` +
      `displayText にはその文の該当語を "_____" にしたもの。` +
      `instruction は「Listen and type the missing word.」。acceptedAnswers は空所にした形1つ。`,
  },
  {
    id: "vt1",
    answerType: "typing",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: true,
    isAvailable: () => true,
    promptSpec: (word) =>
      `vt1: audioText は "${word}"。instruction は「Listen and type the word you hear.」。acceptedAnswers は ["${word}"]。` +
      `3バリエーションとも同一でよい。`,
  },
  {
    id: "vt2",
    answerType: "typing",
    needsDisplayText: false,
    needsAudioText: true,
    correctMustBeWord: false,
    isAvailable: hasExamples,
    promptSpec: (word) =>
      `vt2: audioText に "${word}" を含む短い英文（8語以内目安、毎バリエーション新作）。` +
      `instruction は「Listen and type the sentence you hear.」。acceptedAnswers は audioText と同一の文1つ。`,
  },
];

// -- AI 呼び出し（形式グループ単位）

// 構造化出力の1問分。answer をフラットに持ち、保存時に QuizQuestion へ変換する
interface RawQuestion {
  format: string;
  variantIndex: number;
  instruction: string;
  displayText: string | null;
  audioText: string | null;
  answerType: "choices" | "typing";
  options: string[] | null;
  correctIndex: number | null;
  acceptedAnswers: string[] | null;
}

const QUIZ_QUESTIONS_SCHEMA = {
  type: "object",
  properties: {
    questions: {
      type: "array",
      description: "指定された各形式につき、ちょうど指定数のバリエーション（variantIndex 0..N-1）",
      items: {
        type: "object",
        properties: {
          format: { type: "string", description: "形式ID（指示で列挙したもののみ）" },
          variantIndex: { type: "integer", description: "同一形式内の通し番号（0始まり）" },
          instruction: { type: "string", description: "画面上部に出す簡潔な英語の指示文" },
          displayText: {
            type: ["string", "null"],
            description: "画面に表示する本文（定義・空所付き英文など）。不要な形式は null",
          },
          audioText: {
            type: ["string", "null"],
            description: "TTSで読み上げるテキスト。音声を使わない形式は null",
          },
          answerType: { type: "string", enum: ["choices", "typing"] },
          options: {
            type: ["array", "null"],
            description: "answerType=choices のとき4つ。typing は null",
            items: { type: "string" },
          },
          correctIndex: {
            type: ["integer", "null"],
            description: "answerType=choices のときの正解位置（0..3）。typing は null",
          },
          acceptedAnswers: {
            type: ["array", "null"],
            description: "answerType=typing のときの正解文字列（通常1つ）。choices は null",
            items: { type: "string" },
          },
        },
        required: [
          "format",
          "variantIndex",
          "instruction",
          "displayText",
          "audioText",
          "answerType",
          "options",
          "correctIndex",
          "acceptedAnswers",
        ],
        additionalProperties: false,
      },
    },
  },
  required: ["questions"],
  additionalProperties: false,
} as const;

/// 1呼び出しに含める形式数（出力トークンを callStructured の max_tokens 内に収める）
const FORMATS_PER_CALL = 6;

function buildPrompt(word: string, info: WordInfo, specs: FormatSpec[]): string {
  const material = {
    senses: info.senses.map((s) => ({
      englishDefinition: s.englishDefinition,
      partOfSpeech: englishPartOfSpeech(s.partOfSpeech) ?? s.partOfSpeech,
    })),
    examples: info.examples.map((e) => e.english),
    collocations: info.collocations,
    synonyms: info.synonyms,
    antonyms: info.antonyms,
    inflections: mappableInflections(info),
    cefrLevel: info.cefrLevel,
  };

  return [
    `英単語 "${word}" の復習クイズ問題を生成してください。ESL学習者向けで、問題文・選択肢・指示文はすべて英語です。`,
    `以下の単語情報を意味の基準にしてください（例文や誤答はこれに縛られず新しく作ってよい）:`,
    JSON.stringify(material),
    ``,
    `共通ルール:`,
    `- 各形式につき、ちょうど ${VARIANTS_PER_FORMAT} バリエーション（variantIndex: 0〜${VARIANTS_PER_FORMAT - 1}）を作る`,
    `- バリエーション同士は文・誤答・言い回しを変える（指示で「同一でよい」とした形式を除く）`,
    `- 4択（answerType: "choices"）は options ちょうど4つ・正解は1つだけ・重複なし。誤答は もっともらしいが明確に誤り のもの`,
    `- 難易度は CEFR ${info.cefrLevel ?? "不明"} の学習者向けに調整する`,
    `- 語彙・文はアメリカ英語`,
    ``,
    `生成する形式:`,
    ...specs.map((spec) => `- ${spec.promptSpec(word, info)}`),
  ].join("\n");
}

/// 選択肢の重複判定・正解一致判定に使う正規化キー
function normalizeKey(text: string): string {
  return text.trim().toLowerCase().replace(/[.。!?]+$/u, "");
}

/// AI 出力1件を検証して QuizQuestion に変換する。不正なら null（その variant は捨てる）
function validateAndConvert(raw: RawQuestion, word: string, spec: FormatSpec): QuizQuestion | null {
  if (!raw.instruction?.trim()) return null;
  if (raw.answerType !== spec.answerType) return null;
  if (spec.needsDisplayText && !raw.displayText?.trim()) return null;
  if (spec.needsAudioText && !raw.audioText?.trim()) return null;

  if (spec.answerType === "choices") {
    const options = raw.options ?? [];
    if (options.length !== 4 || options.some((o) => !o.trim())) return null;
    if (new Set(options.map(normalizeKey)).size !== 4) return null;
    if (raw.correctIndex == null || raw.correctIndex < 0 || raw.correctIndex > 3) return null;
    if (spec.correctMustBeWord && normalizeKey(options[raw.correctIndex]) !== normalizeKey(word)) return null;
    return {
      format: spec.id,
      instruction: raw.instruction.trim(),
      displayText: raw.displayText?.trim() || null,
      audioText: raw.audioText?.trim() || null,
      promptIllustrationWord: null,
      answer: {
        type: "choices",
        options,
        correctIndex: raw.correctIndex,
        acceptedAnswers: null,
        matchRateThreshold: null,
      },
    };
  }

  const accepted = (raw.acceptedAnswers ?? []).filter((a) => a.trim());
  if (accepted.length === 0) return null;
  if (spec.correctMustBeWord && !accepted.some((a) => normalizeKey(a) === normalizeKey(word))) return null;
  return {
    format: spec.id,
    instruction: raw.instruction.trim(),
    displayText: raw.displayText?.trim() || null,
    audioText: raw.audioText?.trim() || null,
    promptIllustrationWord: null,
    answer: {
      type: "typing",
      options: null,
      correctIndex: null,
      acceptedAnswers: accepted,
      // 例文ディクテーション（vt2）のみ一致率判定。AI の出力値は使わずサーバで固定する
      matchRateThreshold: spec.id === "vt2" ? SENTENCE_MATCH_THRESHOLD : null,
    },
  };
}

// -- イラスト系4形式（TC11・IC1・IT1・VC8）: AI 不要のルール生成

function pickRandom<T>(pool: T[], count: number): T[] {
  const shuffled = [...pool];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled.slice(0, count);
}

function shuffledChoices(correct: string, wrong: string[]): { options: string[]; correctIndex: number } {
  const options = pickRandom([correct, ...wrong], wrong.length + 1);
  return { options, correctIndex: options.indexOf(correct) };
}

/**
 * イラスト系形式をルール生成する。
 * - illustratedWords: この言語でイラスト生成済みの単語（word_illustrations テーブル。対象単語を含んでよい）
 * - allWords: words テーブスの全単語（IC1 の誤答テキスト用）
 */
export function generateIllustrationQuestions(
  word: string,
  illustratedWords: string[],
  allWords: string[]
): GeneratedQuestion[] {
  const key = normalizeKey(word);
  const hasOwnIllustration = illustratedWords.some((w) => normalizeKey(w) === key);
  if (!hasOwnIllustration) return [];

  const otherIllustrated = illustratedWords.filter((w) => normalizeKey(w) !== key);
  const otherWords = allWords.filter((w) => normalizeKey(w) !== key);
  const questions: GeneratedQuestion[] = [];

  for (let variant = 0; variant < VARIANTS_PER_FORMAT; variant++) {
    // TC11: 単語→イラスト4択 / VC8: 音声→イラスト4択（誤答は他単語の生成済みイラスト3枚）
    if (otherIllustrated.length >= 3) {
      const tc11 = shuffledChoices(word, pickRandom(otherIllustrated, 3));
      questions.push(ruleQuestion(variant, {
        format: "tc11",
        instruction: `Which picture shows “${word}”?`,
        displayText: null,
        audioText: null,
        promptIllustrationWord: null,
        answer: { type: "illustrationChoices", options: tc11.options, correctIndex: tc11.correctIndex, acceptedAnswers: null, matchRateThreshold: null },
      }));
      const vc8 = shuffledChoices(word, pickRandom(otherIllustrated, 3));
      questions.push(ruleQuestion(variant, {
        format: "vc8",
        instruction: "Listen. Which picture shows the word you hear?",
        displayText: null,
        audioText: word,
        promptIllustrationWord: null,
        answer: { type: "illustrationChoices", options: vc8.options, correctIndex: vc8.correctIndex, acceptedAnswers: null, matchRateThreshold: null },
      }));
    }
    // IC1: イラスト→単語4択（誤答は単語帳の他単語テキスト）
    if (otherWords.length >= 3) {
      const ic1 = shuffledChoices(word, pickRandom(otherWords, 3));
      questions.push(ruleQuestion(variant, {
        format: "ic1",
        instruction: "Which word does this picture show?",
        displayText: null,
        audioText: null,
        promptIllustrationWord: word,
        answer: { type: "choices", options: ic1.options, correctIndex: ic1.correctIndex, acceptedAnswers: null, matchRateThreshold: null },
      }));
    }
    // IT1: イラスト→単語入力
    questions.push(ruleQuestion(variant, {
      format: "it1",
      instruction: "Type the word this picture shows.",
      displayText: null,
      audioText: null,
      promptIllustrationWord: word,
      answer: { type: "typing", options: null, correctIndex: null, acceptedAnswers: [word], matchRateThreshold: null },
    }));
  }
  return questions;
}

function ruleQuestion(variantIndex: number, question: QuizQuestion): GeneratedQuestion {
  return { question, variantIndex, model: "rule", inputTokens: 0, outputTokens: 0 };
}

// -- エントリポイント

/**
 * 1単語分の問題を生成する（AI 23形式 + ルール生成のイラスト系）。
 * 形式グループごとに並列で callStructured を呼び、失敗したグループはスキップして部分成功を返す。
 */
export async function generateQuizQuestions(
  word: string,
  info: WordInfo,
  illustratedWords: string[],
  allWords: string[]
): Promise<QuizGenerationResult> {
  const availableSpecs = AI_FORMAT_SPECS.filter((spec) => spec.isAvailable(info));
  const groups: FormatSpec[][] = [];
  for (let i = 0; i < availableSpecs.length; i += FORMATS_PER_CALL) {
    groups.push(availableSpecs.slice(i, i + FORMATS_PER_CALL));
  }

  const results = await Promise.allSettled(
    groups.map(async (specs) => {
      // 1グループ 最大18問（6形式×3）のJSONを確実に収めるため max_tokens を広めに取る
      const { json, inputTokens, outputTokens } = await callStructured<{ questions: RawQuestion[] }>(
        config.quizQuestionModel,
        QUIZ_QUESTIONS_SCHEMA,
        [{ type: "text", text: buildPrompt(word, info, specs) }],
        8192
      );
      const specById = new Map(specs.map((spec) => [spec.id, spec]));
      const valid: GeneratedQuestion[] = [];
      const variantCounts = new Map<string, number>();
      for (const raw of json.questions ?? []) {
        const spec = specById.get(raw.format);
        if (!spec) continue;
        const count = variantCounts.get(spec.id) ?? 0;
        if (count >= VARIANTS_PER_FORMAT) continue;
        const question = validateAndConvert(raw, word, spec);
        if (!question) continue;
        // variantIndex は AI 出力を信用せず、形式内の受理順で振り直す
        valid.push({ question, variantIndex: count, model: config.quizQuestionModel, inputTokens: 0, outputTokens: 0 });
        variantCounts.set(spec.id, count + 1);
      }
      // トークンはグループ内の受理済み問題へ均等按分する（合計が実測に一致するよう最後に残余を足す）
      if (valid.length > 0) {
        const inPer = Math.floor(inputTokens / valid.length);
        const outPer = Math.floor(outputTokens / valid.length);
        valid.forEach((q, index) => {
          q.inputTokens = inPer + (index === 0 ? inputTokens - inPer * valid.length : 0);
          q.outputTokens = outPer + (index === 0 ? outputTokens - outPer * valid.length : 0);
        });
      }
      return { valid, inputTokens, outputTokens };
    })
  );

  const questions: GeneratedQuestion[] = [];
  const errors: string[] = [];
  let totalInputTokens = 0;
  let totalOutputTokens = 0;
  results.forEach((result, index) => {
    if (result.status === "fulfilled") {
      questions.push(...result.value.valid);
      totalInputTokens += result.value.inputTokens;
      totalOutputTokens += result.value.outputTokens;
    } else {
      const formats = groups[index].map((spec) => spec.id).join(",");
      const message = result.reason instanceof Error ? result.reason.message : String(result.reason);
      errors.push(`group[${formats}]: ${message}`);
    }
  });

  questions.push(...generateIllustrationQuestions(word, illustratedWords, allWords));
  return { questions, errors, totalInputTokens, totalOutputTokens };
}
