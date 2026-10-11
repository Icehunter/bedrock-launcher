import { Section } from "../components/Section";
import { asset } from "../site";

const PAGES: { id: string; icon: string; shot: string; height: number; title: string; text: string[] }[] = [
  {
    id: "play",
    icon: "play",
    shot: "play.jpg",
    height: 1066,
    title: "Play",
    text: [
      "Pick a profile and press Play. The status panel shows the installed game, linked packs, pack errors from the last run and how the last session ended.",
      "Each profile has a name, a game version, its own data folder for worlds and settings, and an optional window size. The pencil button edits the profile.",
    ],
  },
  {
    id: "content",
    icon: "content",
    shot: "content.png",
    height: 840,
    title: "Content",
    text: [
      "Install .mcpack, .mcaddon and .mcworld files. The game starts and imports them. Paste a minecraft:// link to open it in the game.",
      "Open the game folders for worlds and packs, link a pack folder you are working on so it loads straight into the game, and read the pack errors from the last run.",
    ],
  },
  {
    id: "versions",
    icon: "versions",
    shot: "versions.png",
    height: 690,
    title: "Versions",
    text: [
      "Get the game with Download from Google Play, or click Import Files and pick a .mcversion file or the APK files kept from a Google Play download.",
      "Export saves an installed version as one .mcversion file, so you can set up your other Mac without signing in to Google there.",
    ],
  },
  {
    id: "log",
    icon: "log",
    shot: "log.png",
    height: 1066,
    title: "Game Log",
    text: [
      "The game's output while it runs. Copy it or save it to a file when you need help with a pack or a crash.",
    ],
  },
  {
    id: "settings",
    icon: "settings",
    shot: "settings.png",
    height: 840,
    title: "Settings",
    text: [
      "Hide the launcher while the game runs, check for launcher updates when it opens, and open the launcher data folder.",
      "Sign in to Google or sign out. Signing in is only needed to download the game from Google Play.",
    ],
  },
];

export default function Guide() {
  return (
    <Section title="Guide" intro="What each page of the launcher does.">
      <div className="flex flex-col gap-16">
        {PAGES.map((p) => (
          <article key={p.id} id={p.id} className="grid items-start gap-6 lg:grid-cols-[1fr_1.6fr]">
            <div>
              <h3 className="flex items-center gap-3 text-2xl font-black">
                <img src={asset(`icons/${p.icon}.png`)} alt="" width={32} height={32} className="pixel" />
                {p.title}
              </h3>
              {p.text.map((t) => (
                <p key={t} className="mt-3 leading-relaxed text-muted">
                  {t}
                </p>
              ))}
            </div>
            <img
              src={asset(`shots/${p.shot}`)}
              alt={`The ${p.title} page of Bedrock Launcher`}
              loading="lazy"
              width={1568}
              height={p.height}
              className="h-auto w-full rounded-xl border border-[var(--bl-edge)] shadow-[0_12px_32px_rgb(0_0_0/0.45)]"
            />
          </article>
        ))}
      </div>
    </Section>
  );
}
