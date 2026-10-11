import { Card } from "@heroui/react";
import { BlockButton } from "../components/BlockButton";
import { Section } from "../components/Section";
import { DOWNLOAD_URL, asset } from "../site";

const STEPS = [
  {
    title: "Download the launcher",
    text: "Get the .dmg file from the latest release on GitHub.",
  },
  {
    title: "Drag it to Applications",
    text: "Open the .dmg and drag Bedrock Launcher to Applications. Releases are signed with a Developer ID and notarized by Apple, so macOS opens it without a warning.",
  },
  {
    title: "Open it and get the game",
    text: "The first time, the Versions page is where you get Minecraft. Pick one of the two ways below.",
  },
];

const WAYS = [
  {
    art: "install-play.png",
    title: "Download from Google Play",
    text: "On the Versions page, pick a version and click Download from Google Play. The first time, sign in to Google with the account that owns Minecraft. The launcher offers only the versions it is tested with.",
  },
  {
    art: "install-move.png",
    title: "Move your copy from your other Mac",
    text: "On the Mac that already has the game, click Export next to the version to save it as one .mcversion file. Copy that file over, then click Import Files on this Mac. No Google sign-in is needed here, which suits a child's Mac.",
  },
];

export default function Install() {
  return (
    <>
      <Section title="Install" intro="You need a Mac with Apple Silicon and macOS 15 or newer.">
        <ol className="flex max-w-3xl flex-col gap-6">
          {STEPS.map((s, i) => (
            <li key={s.title} className="flex gap-4">
              <span
                className="flex h-10 w-10 shrink-0 items-center justify-center border-2 border-[var(--bl-edge)] bg-[var(--bl-green)] text-lg font-black text-white"
                aria-hidden="true"
              >
                {i + 1}
              </span>
              <div>
                <h3 className="text-lg font-black">{s.title}</h3>
                <p className="mt-1 text-muted">{s.text}</p>
              </div>
            </li>
          ))}
        </ol>
        <div className="mt-8">
          <BlockButton tone="green" href={DOWNLOAD_URL}>
            Download for Mac
          </BlockButton>
        </div>
      </Section>

      <Section id="game" title="Get the Game" intro="The game is not included. It comes from your own Google Play account.">
        <div className="grid gap-4 md:grid-cols-2">
          {WAYS.map((w) => (
            <Card key={w.title} className="overflow-hidden p-0">
              <img src={asset(`art/${w.art}`)} alt="" width={960} height={540} className="h-auto w-full" />
              <Card.Header className="px-4 pt-4">
                <Card.Title className="text-lg font-black">{w.title}</Card.Title>
              </Card.Header>
              <Card.Content className="px-4 pb-5">
                <p className="text-muted">{w.text}</p>
              </Card.Content>
            </Card>
          ))}
        </div>
        <p className="mt-6 max-w-3xl text-sm text-muted">
          Import Files also takes the APK files kept from a Google Play download, when Keep downloaded APK files is on in Settings.
        </p>
      </Section>
    </>
  );
}
