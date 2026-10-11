import { Card } from "@heroui/react";
import { Download, Gamepad2, Play } from "lucide-react";
import type { ReactNode } from "react";
import { BlockButton } from "../components/BlockButton";
import { Hero, REQUIREMENTS } from "../components/Hero";
import { Section } from "../components/Section";
import { DOWNLOAD_URL, asset } from "../site";

const STEPS: { icon: ReactNode; title: string; text: string }[] = [
  {
    icon: <Download size={28} aria-hidden="true" />,
    title: "Get the launcher",
    text: "Download the app and drag it to Applications. It is signed and notarized, so it opens without a warning.",
  },
  {
    icon: <Gamepad2 size={28} aria-hidden="true" />,
    title: "Get the game",
    text: "Sign in to Google Play with the account that owns Minecraft, or import the copy you exported from your other Mac.",
  },
  {
    icon: <Play size={28} aria-hidden="true" />,
    title: "Play",
    text: "Pick a profile and press Play. The game opens in its own window on your Mac.",
  },
];

const FEATURES: { icon: string; title: string; text: string }[] = [
  {
    icon: "content",
    title: "Packs and worlds",
    text: "Install .mcpack, .mcaddon and .mcworld files, open minecraft:// links, and see pack errors from the last run.",
  },
  {
    icon: "versions",
    title: "Several game versions",
    text: "Keep more than one version installed. Export a version as one file to set up another Mac.",
  },
  {
    icon: "play",
    title: "Profiles",
    text: "Each profile picks a game version, its own folder for worlds and settings, and a window size.",
  },
  {
    icon: "log",
    title: "Game log",
    text: "Watch the game's output while it runs, which helps when a pack or add-on misbehaves.",
  },
];

export default function Home() {
  return (
    <>
      <Hero />

      <Section id="how" title="How It Works" intro="Three steps from a fresh Mac to a running game.">
        <ol className="grid gap-4 md:grid-cols-3">
          {STEPS.map((s, i) => (
            <li key={s.title}>
              <Card className="h-full">
                <Card.Header className="flex flex-row items-center gap-3">
                  <span className="flex h-12 w-12 shrink-0 items-center justify-center border-2 border-[var(--bl-edge)] bg-[var(--bl-green)] text-white">
                    {s.icon}
                  </span>
                  <Card.Title className="text-lg font-black">
                    {i + 1}. {s.title}
                  </Card.Title>
                </Card.Header>
                <Card.Content>
                  <p className="text-muted">{s.text}</p>
                </Card.Content>
              </Card>
            </li>
          ))}
        </ol>
      </Section>

      <Section id="features" title="What You Can Do">
        <div className="grid gap-4 sm:grid-cols-2">
          {FEATURES.map((f) => (
            <Card key={f.title}>
              <Card.Header className="flex flex-row items-center gap-3">
                <img src={asset(`icons/${f.icon}.png`)} alt="" width={32} height={32} className="pixel" />
                <Card.Title className="text-lg font-black">{f.title}</Card.Title>
              </Card.Header>
              <Card.Content>
                <p className="text-muted">{f.text}</p>
              </Card.Content>
            </Card>
          ))}
        </div>
      </Section>

      <Section id="get" title="Ready to Play?">
        <p className="max-w-2xl text-muted">
          You need a Mac with Apple Silicon running macOS 15 or newer, and a copy of Minecraft for
          Android on your Google account or exported from your other Mac.
        </p>
        <div className="mt-6 flex flex-wrap items-center gap-4">
          <BlockButton tone="green" href={DOWNLOAD_URL}>
            Download for Mac
          </BlockButton>
          <BlockButton tone="slate" to="/install">
            Install guide
          </BlockButton>
        </div>
        <p className="mt-4 text-xs font-semibold text-muted">{REQUIREMENTS}</p>
      </Section>
    </>
  );
}
