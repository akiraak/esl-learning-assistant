// 長文TTSの動作確認スクリプト（docs/plans/tts-long-text.md）
// 使い方: npx ts-node scripts/tts-long-check.ts [文字数]
import "dotenv/config";
import { splitTextIntoChunks, synthesizeSpeech } from "../src/tts";

const BASE =
  "The little fox trotted along the winding forest path, pausing now and then to sniff the cool morning air. " +
  "Sunlight filtered through the tall pine trees, painting golden patterns on the soft carpet of fallen needles. " +
  "Far away, a woodpecker tapped a steady rhythm, and the stream murmured quietly over smooth gray stones. ";

function makeText(targetChars: number): string {
  let s = "";
  let i = 0;
  while (s.length < targetChars) s += BASE.replace("little fox", `little fox number ${++i}`);
  return s.slice(0, s.lastIndexOf(".", targetChars) + 1);
}

async function main() {
  // 分割ロジックの確認
  const cases = [
    "Hello.",
    makeText(1000),
    makeText(4000),
    "a".repeat(3200), // 空白なし・文境界なしの極端ケース
    "word ".repeat(1000).trim(), // 1文が上限超え
  ];
  for (const text of cases) {
    const chunks = splitTextIntoChunks(text);
    const total = chunks.reduce((n, c) => n + c.length, 0);
    const max = Math.max(...chunks.map((c) => c.length));
    console.log(
      `split: input=${text.length} chunks=${chunks.length} maxChunk=${max} totalChars=${total}`
    );
    if (max > 1600) throw new Error("chunk too large");
  }

  const target = Number(process.argv[2] ?? 0);
  if (!target) {
    console.log("(APIを呼ぶには文字数を引数で指定: npx ts-node scripts/tts-long-check.ts 4000)");
    return;
  }
  const text = makeText(target);
  console.log(`synthesize: chars=${text.length} chunks=${splitTextIntoChunks(text).length} ...`);
  const started = Date.now();
  const wav = await synthesizeSpeech(text, "chobi", "flash");
  const seconds = (wav.length - 44) / (24000 * 2);
  console.log(
    `done: wavBytes=${wav.length} audioSec=${seconds.toFixed(1)} charsPerSec=${(text.length / seconds).toFixed(1)} latencyMs=${Date.now() - started}`
  );
  require("fs").writeFileSync("/tmp/tts-long-check.wav", wav);
  console.log("saved: /tmp/tts-long-check.wav");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
