import { describe, expect, it } from "vitest";
import { fetchReleases } from "./releases";

const apiRelease = (over: Record<string, unknown> = {}) => ({
  tag_name: "v0.1.1",
  name: "Bedrock Launcher 0.1.1",
  published_at: "2026-10-11T02:38:46Z",
  body: "Notes",
  html_url: "https://github.com/Icehunter/bedrock-launcher/releases/tag/v0.1.1",
  draft: false,
  prerelease: false,
  assets: [
    {
      name: "Bedrock-Launcher-0.1.1.dmg",
      browser_download_url: "https://github.com/Icehunter/bedrock-launcher/releases/download/v0.1.1/Bedrock-Launcher-0.1.1.dmg",
      size: 52428800,
    },
  ],
  ...over,
});

const respond = (status: number, json: unknown) =>
  (async () => new Response(JSON.stringify(json), { status })) as unknown as typeof fetch;

describe("fetchReleases", () => {
  it("maps a release with a dmg", async () => {
    const r = await fetchReleases(respond(200, [apiRelease()]));
    expect(r.ok).toBe(true);
    if (!r.ok) return;
    expect(r.releases[0].tag).toBe("v0.1.1");
    expect(r.releases[0].name).toBe("Bedrock Launcher 0.1.1");
    expect(r.releases[0].date).toBe("2026-10-11T02:38:46Z");
    expect(r.releases[0].dmg?.name).toBe("Bedrock-Launcher-0.1.1.dmg");
    expect(r.releases[0].dmg?.size).toBe(52428800);
  });

  it("release without dmg has no dmg field", async () => {
    const r = await fetchReleases(respond(200, [apiRelease({ assets: [{ name: "notes.txt", browser_download_url: "x", size: 1 }] })]));
    expect(r.ok && r.releases[0].dmg).toBe(undefined);
  });

  it("empty body is kept as empty string", async () => {
    const r = await fetchReleases(respond(200, [apiRelease({ body: null })]));
    expect(r.ok && r.releases[0].body).toBe("");
  });

  it("missing name falls back to the tag", async () => {
    const r = await fetchReleases(respond(200, [apiRelease({ name: "" })]));
    expect(r.ok && r.releases[0].name).toBe("v0.1.1");
  });

  it("skips drafts and prereleases", async () => {
    const r = await fetchReleases(
      respond(200, [apiRelease({ tag_name: "v0.2.0", draft: true }), apiRelease({ tag_name: "v0.2.0-rc1", prerelease: true }), apiRelease()]),
    );
    expect(r.ok && r.releases.map((x) => x.tag)).toEqual(["v0.1.1"]);
  });

  it("rate limited returns ok false", async () => {
    expect(await fetchReleases(respond(403, { message: "API rate limit exceeded" }))).toEqual({ ok: false });
  });

  it("network error returns ok false", async () => {
    const failing = (async () => {
      throw new TypeError("Failed to fetch");
    }) as unknown as typeof fetch;
    expect(await fetchReleases(failing)).toEqual({ ok: false });
  });

  it("non-array body returns ok false", async () => {
    expect(await fetchReleases(respond(200, { message: "Not Found" }))).toEqual({ ok: false });
  });
});
