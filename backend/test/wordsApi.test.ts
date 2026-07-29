import { describe, it } from "node:test";
import assert from "node:assert/strict";
import {
  buildWordDetail,
  buildWordSummary,
  parseWordListQuery,
  WORD_LIST_LIMIT_DEFAULT,
  WORD_LIST_LIMIT_MAX,
} from "../src/wordsApi";
import type { StoredWordRow } from "../src/db";

function makeRow(overrides: Partial<StoredWordRow> = {}): StoredWordRow {
  return {
    id: 1,
    word: "apple",
    target_language: "ja",
    word_info_json: JSON.stringify({
      senses: [
        { meaning: "りんご", englishDefinition: "a round fruit", partOfSpeech: "名詞", note: null },
      ],
      pronunciation: { ipa: "/ˈæp.əl/", syllables: "AP-ple" },
      inflections: [],
      examples: [],
      collocations: [],
      synonyms: [],
      antonyms: [],
      usageNote: null,
      cefrLevel: "A1",
      etymology: null,
      register: null,
      commonMistakes: null,
    }),
    model: "claude-test",
    context: null,
    user_translation: null,
    created_at: "2026-07-01T00:00:00.000Z",
    updated_at: "2026-07-02T00:00:00.000Z",
    generation_count: 1,
    ...overrides,
  };
}

describe("parseWordListQuery", () => {
  it("空クエリはデフォルト値になる", () => {
    const result = parseWordListQuery({});
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.deepEqual(result.value, {
      limit: WORD_LIST_LIMIT_DEFAULT,
      offset: 0,
      includeInfo: false,
    });
  });

  it("全パラメータ指定を受け付ける", () => {
    const result = parseWordListQuery({
      targetLanguage: "ja",
      q: " app ",
      updatedSince: "2026-07-01T00:00:00Z",
      limit: "50",
      offset: "10",
      includeInfo: "true",
    });
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.value.targetLanguage, "ja");
    assert.equal(result.value.q, "app");
    assert.equal(result.value.updatedSince, "2026-07-01T00:00:00.000Z");
    assert.equal(result.value.limit, 50);
    assert.equal(result.value.offset, 10);
    assert.equal(result.value.includeInfo, true);
  });

  it("updatedSince はオフセット付きでも UTC ISO に正規化される", () => {
    const result = parseWordListQuery({ updatedSince: "2026-07-01T09:00:00+09:00" });
    assert.equal(result.ok, true);
    if (!result.ok) return;
    assert.equal(result.value.updatedSince, "2026-07-01T00:00:00.000Z");
  });

  it("不正な updatedSince は拒否する", () => {
    const result = parseWordListQuery({ updatedSince: "not-a-date" });
    assert.equal(result.ok, false);
  });

  it("limit の境界値: 1 と最大値は通り、0・最大値+1・小数・非数値は拒否する", () => {
    assert.equal(parseWordListQuery({ limit: "1" }).ok, true);
    assert.equal(parseWordListQuery({ limit: String(WORD_LIST_LIMIT_MAX) }).ok, true);
    assert.equal(parseWordListQuery({ limit: "0" }).ok, false);
    assert.equal(parseWordListQuery({ limit: String(WORD_LIST_LIMIT_MAX + 1) }).ok, false);
    assert.equal(parseWordListQuery({ limit: "1.5" }).ok, false);
    assert.equal(parseWordListQuery({ limit: "abc" }).ok, false);
    assert.equal(parseWordListQuery({ limit: "-1" }).ok, false);
  });

  it("offset は 0 を許可し、負数・非数値は拒否する", () => {
    const zero = parseWordListQuery({ offset: "0" });
    assert.equal(zero.ok, true);
    assert.equal(parseWordListQuery({ offset: "-1" }).ok, false);
    assert.equal(parseWordListQuery({ offset: "abc" }).ok, false);
  });

  it("includeInfo は true/false のみ受け付ける", () => {
    assert.equal(parseWordListQuery({ includeInfo: "false" }).ok, true);
    assert.equal(parseWordListQuery({ includeInfo: "1" }).ok, false);
  });

  it("配列で来たパラメータ（?q=a&q=b）は拒否する", () => {
    assert.equal(parseWordListQuery({ q: ["a", "b"] }).ok, false);
    assert.equal(parseWordListQuery({ targetLanguage: ["ja", "en"] }).ok, false);
  });

  it("空文字の targetLanguage / q は拒否する", () => {
    assert.equal(parseWordListQuery({ targetLanguage: " " }).ok, false);
    assert.equal(parseWordListQuery({ q: "" }).ok, false);
  });
});

describe("buildWordSummary", () => {
  it("第1義のサマリを取り出す", () => {
    const summary = buildWordSummary(makeRow(), false);
    assert.equal(summary.word, "apple");
    assert.equal(summary.targetLanguage, "ja");
    assert.equal(summary.meaning, "りんご");
    assert.equal(summary.partOfSpeech, "名詞");
    assert.equal(summary.cefrLevel, "A1");
    assert.equal(summary.createdAt, "2026-07-01T00:00:00.000Z");
    assert.equal(summary.updatedAt, "2026-07-02T00:00:00.000Z");
    assert.equal("wordInfo" in summary, false);
  });

  it("includeInfo=true で wordInfo 全体を含める", () => {
    const summary = buildWordSummary(makeRow(), true);
    assert.equal(summary.wordInfo?.pronunciation.ipa, "/ˈæp.əl/");
  });

  it("壊れた JSON でもサマリ null で返す（エラーにしない）", () => {
    const summary = buildWordSummary(makeRow({ word_info_json: "{broken" }), true);
    assert.equal(summary.meaning, null);
    assert.equal(summary.partOfSpeech, null);
    assert.equal(summary.cefrLevel, null);
    assert.equal(summary.wordInfo, null);
  });

  it("senses が空でもサマリ null で返す", () => {
    const summary = buildWordSummary(
      makeRow({ word_info_json: JSON.stringify({ senses: [], cefrLevel: null }) }),
      false
    );
    assert.equal(summary.meaning, null);
    assert.equal(summary.partOfSpeech, null);
  });
});

describe("buildWordDetail", () => {
  it("保存行を詳細レスポンスに整形する", () => {
    const detail = buildWordDetail(makeRow());
    assert.ok(detail);
    assert.equal(detail.word, "apple");
    assert.equal(detail.targetLanguage, "ja");
    assert.equal(detail.model, "claude-test");
    assert.equal(detail.generationCount, 1);
    assert.equal(detail.wordInfo.senses[0].meaning, "りんご");
  });

  it("壊れた JSON は null を返す（ルート側で 500 にする）", () => {
    assert.equal(buildWordDetail(makeRow({ word_info_json: "not json" })), null);
  });
});
