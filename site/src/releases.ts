export type Release = {
  tag: string;
  name: string;
  date: string;
  body: string;
  url: string;
  dmg?: { name: string; url: string; size: number };
};

export type ReleasesResult = { ok: true; releases: Release[] } | { ok: false };

export const RELEASES_API = "https://api.github.com/repos/Icehunter/bedrock-launcher/releases";

type ApiAsset = { name: string; browser_download_url: string; size: number };
type ApiRelease = {
  tag_name: string;
  name: string | null;
  published_at: string;
  body: string | null;
  html_url: string;
  draft: boolean;
  prerelease: boolean;
  assets: ApiAsset[];
};

/** Stable releases from GitHub, newest first. Any failure gives { ok: false }. */
export async function fetchReleases(fetchImpl: typeof fetch = fetch): Promise<ReleasesResult> {
  try {
    const res = await fetchImpl(RELEASES_API, { headers: { Accept: "application/vnd.github+json" } });
    if (!res.ok) return { ok: false };
    const data: unknown = await res.json();
    if (!Array.isArray(data)) return { ok: false };
    const releases = (data as ApiRelease[])
      .filter((r) => !r.draft && !r.prerelease)
      .map((r): Release => {
        const dmg = r.assets?.find((a) => a.name.endsWith(".dmg"));
        return {
          tag: r.tag_name,
          name: r.name || r.tag_name,
          date: r.published_at,
          body: r.body ?? "",
          url: r.html_url,
          ...(dmg ? { dmg: { name: dmg.name, url: dmg.browser_download_url, size: dmg.size } } : {}),
        };
      });
    return { ok: true, releases };
  } catch {
    return { ok: false };
  }
}
