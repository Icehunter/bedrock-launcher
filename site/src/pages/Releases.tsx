import { useEffect, useState } from "react";
import { Card, Chip, Skeleton } from "@heroui/react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import { BlockButton } from "../components/BlockButton";
import { Section } from "../components/Section";
import { fetchReleases, type ReleasesResult } from "../releases";
import { RELEASES_URL } from "../site";
import tested from "../../../tested-versions.json";

const formatDate = (iso: string) =>
  new Date(iso).toLocaleDateString(undefined, { year: "numeric", month: "long", day: "numeric" });

const formatSize = (bytes: number) => `${(bytes / 1024 / 1024).toFixed(1)} MB`;

function ReleaseList() {
  const [result, setResult] = useState<ReleasesResult | null>(null);
  useEffect(() => {
    let live = true;
    fetchReleases().then((r) => live && setResult(r));
    return () => {
      live = false;
    };
  }, []);

  if (!result) {
    return (
      <div className="flex flex-col gap-4" aria-busy="true" aria-label="Loading releases">
        {[0, 1].map((i) => (
          <Card key={i}>
            <Card.Content className="flex flex-col gap-3">
              <Skeleton className="h-6 w-1/3 rounded-lg" />
              <Skeleton className="h-4 w-1/4 rounded-lg" />
              <Skeleton className="h-16 w-full rounded-lg" />
            </Card.Content>
          </Card>
        ))}
      </div>
    );
  }

  if (!result.ok || result.releases.length === 0) {
    return (
      <Card>
        <Card.Content className="flex flex-col items-start gap-4">
          <p className="text-muted">The release list could not be loaded here. All releases are on GitHub.</p>
          <BlockButton tone="slate" href={RELEASES_URL}>
            Releases on GitHub
          </BlockButton>
        </Card.Content>
      </Card>
    );
  }

  return (
    <ol className="flex flex-col gap-4">
      {result.releases.map((r, i) => (
        <li key={r.tag}>
          <Card>
            <Card.Header className="flex flex-row flex-wrap items-center gap-3">
              <Card.Title className="text-xl font-black">
                <a href={r.url} target="_blank" rel="noopener noreferrer" className="hover:underline">
                  {r.name}
                </a>
              </Card.Title>
              {i === 0 && (
                <Chip color="success" variant="soft" size="sm">
                  Latest
                </Chip>
              )}
              <span className="text-sm text-muted">{formatDate(r.date)}</span>
            </Card.Header>
            <Card.Content className="flex flex-col gap-4">
              {r.body && (
                <div className="release-notes text-sm">
                  <ReactMarkdown
                    remarkPlugins={[remarkGfm]}
                    components={{ a: (props) => <a {...props} target="_blank" rel="noopener noreferrer" /> }}
                  >
                    {r.body}
                  </ReactMarkdown>
                </div>
              )}
              {r.dmg && (
                <div className="flex flex-wrap items-center gap-3">
                  <BlockButton tone="green" href={r.dmg.url}>
                    Download {r.dmg.name}
                  </BlockButton>
                  <span className="text-sm text-muted">{formatSize(r.dmg.size)}</span>
                </div>
              )}
            </Card.Content>
          </Card>
        </li>
      ))}
    </ol>
  );
}

export default function Releases() {
  return (
    <Section title="Releases" intro="Each launcher release, newest first, and the game versions it is tested with.">
      <Card className="mb-6">
        <Card.Header>
          <Card.Title className="text-lg font-black">Tested Game Versions</Card.Title>
        </Card.Header>
        <Card.Content className="flex flex-col gap-3">
          <div className="flex flex-wrap gap-2">
            {tested.versions.map((v) => (
              <Chip key={v.versionCode} variant="soft">
                {v.name}
              </Chip>
            ))}
          </div>
          <p className="text-sm text-muted">
            Download from Google Play offers these versions only. When Google Play has a newer game, the
            launcher shows a red bar until a release adds it here.
          </p>
        </Card.Content>
      </Card>
      <ReleaseList />
    </Section>
  );
}
