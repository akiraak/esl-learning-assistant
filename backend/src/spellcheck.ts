// 執筆画面（/admin/writing/:id）の綴り検査。判定はサーバ側で行い、クライアントには
// 「本文中のどの範囲が誤りか」だけを返す（辞書 557KB をブラウザへ配らずに済む）。
// db.ts を読み込まない純粋モジュールにして backend/test/spellcheck.test.ts から検証する
// （compositionView.ts / printView.ts と同じ方針）。例外語は呼び出し側が引数で渡す。

// typo-js は型定義を持たない CommonJS パッケージ。en_US 辞書（hunspell 形式）を同梱している。
// eslint-disable-next-line @typescript-eslint/no-var-requires
const Typo = require("typo-js") as new (name: string) => {
  check(word: string): boolean;
  suggest(word: string, limit?: number): string[];
};

export interface Misspelling {
  /// text 内の文字オフセット（終端は排他。text.slice(start, end) === word）
  start: number;
  end: number;
  word: string;
}

const MAX_SUGGESTIONS = 3;

// 辞書のロードは 100ms 強かかるので、プロセス内で 1 度だけ行いメモリに常駐させる。
let dictionary: InstanceType<typeof Typo> | null = null;

function loadDictionary(): InstanceType<typeof Typo> {
  if (!dictionary) dictionary = new Typo("en_US");
  return dictionary;
}

/// 語として判定してよい文字だけで構成されているか。
/// 数字（`2026`）・ピリオド（`U.S.`）・URL・メール・日本語はここで弾く。
/// 辞書に無く必ず誤検出になるものを、判定に回す前に落とすのが目的。
const CHECKABLE = /^[A-Za-z'’-]+$/;

const HAS_LETTER = /[A-Za-z]/;

/// 前後の記号を落とした範囲を返す（`"Hello,"` → `Hello`、`'cause` → `cause`）。
/// 語が残らなければ null。引用符の中の語を誤りにしないため、端のアポストロフィも落とす。
function trimToWord(text: string, start: number, end: number): [number, number] | null {
  let s = start;
  let e = end;
  while (s < e && !/[A-Za-z0-9]/.test(text[s])) s += 1;
  while (e > s && !/[A-Za-z0-9]/.test(text[e - 1])) e -= 1;
  return s < e ? [s, e] : null;
}

/// タイポグラフィのアポストロフィ（’）を辞書の持つ ASCII 版に寄せる。
/// `doesn’t` は正規化しないと辞書に無い扱いになる。
function normalizeForDictionary(word: string): string {
  return word.replace(/’/g, "'");
}

/// ハイフン付き複合語（`well-known`）を片ごとに分ける。辞書は複合語を持たないため、
/// 分けずに判定すると正しい綴りでも誤りになる。返すのは text に対するオフセット。
function splitHyphenated(text: string, start: number, end: number): [number, number][] {
  const parts: [number, number][] = [];
  let cursor = start;
  for (let i = start; i <= end; i += 1) {
    if (i === end || text[i] === "-") {
      if (cursor < i) parts.push([cursor, i]);
      cursor = i + 1;
    }
  }
  return parts;
}

/// text を語に切り出し、辞書にも例外語にも無いものを返す。
/// ignoredWords は trim + 小文字化して照合する（単語帳の登録語・無視リスト）。
export function findMisspellings(text: string, ignoredWords: Iterable<string> = []): Misspelling[] {
  if (!text.trim()) return [];

  const ignored = new Set<string>();
  for (const word of ignoredWords) {
    const key = normalizeForDictionary(word).trim().toLowerCase();
    if (key) ignored.add(key);
  }

  const dict = loadDictionary();
  const result: Misspelling[] = [];

  // 空白で切った塊 → 前後の記号を落とす → 判定対象か絞る → ハイフンで分ける、の 4 段。
  // 1 本の正規表現にまとめると規則が読めなくなるので分けてある。
  for (const match of text.matchAll(/\S+/g)) {
    const chunkStart = match.index ?? 0;
    const trimmed = trimToWord(text, chunkStart, chunkStart + match[0].length);
    if (!trimmed) continue;

    const chunk = text.slice(trimmed[0], trimmed[1]);
    if (!CHECKABLE.test(chunk) || !HAS_LETTER.test(chunk)) continue;

    for (const [start, end] of splitHyphenated(text, trimmed[0], trimmed[1])) {
      const raw = text.slice(start, end);
      const word = normalizeForDictionary(raw);
      if (!HAS_LETTER.test(word)) continue;
      if (ignored.has(word.toLowerCase())) continue;
      if (dict.check(word)) continue;

      result.push({ start, end, word: raw });
    }
  }

  return result;
}

// 修正候補は 1 語あたり 1 秒以上かかる（check の方は 20,000 回で 1ms）。本文全体に対して
// まとめて出すと入力のたびに数秒待つことになるので、候補は「赤い語をクリックした時に
// その語だけ」求める。同じ語を何度も引くのでプロセス内にキャッシュする。
const suggestionCache = new Map<string, string[]>();

/// 誤りの語に対する修正候補（最大 3 件）。綴りが正しい語には空配列を返す。
export function suggestCorrections(word: string): string[] {
  const normalized = normalizeForDictionary(word).trim();
  if (!normalized || !CHECKABLE.test(normalized) || !HAS_LETTER.test(normalized)) return [];

  const cached = suggestionCache.get(normalized);
  if (cached) return cached;

  const dict = loadDictionary();
  const suggestions = dict.check(normalized)
    ? []
    : dict.suggest(normalized).slice(0, MAX_SUGGESTIONS);
  suggestionCache.set(normalized, suggestions);
  return suggestions;
}
