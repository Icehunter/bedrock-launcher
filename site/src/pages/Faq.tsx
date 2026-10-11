import { Accordion } from "@heroui/react";
import type { ReactNode } from "react";
import { Section } from "../components/Section";

const DATA = "~/Library/Application Support/BedrockLauncher";

const ITEMS: { q: string; a: ReactNode }[] = [
  {
    q: "Does it come with the game?",
    a: "No. The launcher downloads Minecraft for Android from Google Play with your own Google account, or imports a copy you exported from your other Mac. You need to own the game on Google Play.",
  },
  {
    q: "Does it work on Intel Macs?",
    a: "No. It needs a Mac with Apple Silicon (M1 or newer) and macOS 15 or newer.",
  },
  {
    q: "Is this an official Minecraft product?",
    a: "No. It is a free, open source launcher built on the minecraft-linux project. It is not approved by or associated with Mojang or Microsoft.",
  },
  {
    q: "Can I sign in with my Microsoft account?",
    a: "Yes. When the game asks you to sign in, the launcher opens a Microsoft sign-in window. Each profile keeps its own saved sign-in in its data folder.",
  },
  {
    q: "What does the red bar at the top mean?",
    a: "Google Play has a newer Minecraft than this launcher is tested with. Downloads stay on the newest tested version, and the game you have keeps working. A later launcher release adds the new version.",
  },
  {
    q: "What happens to my Google sign-in?",
    a: (
      <>
        The launcher keeps the Google Play sign-in in <code>{DATA}/google</code>, a folder only your user
        can open. It is used only to download the game. To sign out, open Settings and click Sign Out under
        Google account, which deletes that folder.
      </>
    ),
  },
  {
    q: "How do I get launcher updates?",
    a: "When it opens, the launcher checks GitHub for a newer release and shows a green bar with a link to the download page. You can turn this off in Settings.",
  },
  {
    q: "Can I use mods?",
    a: "Packs and add-ons work today from the Content page. Browsing and installing launcher mods is planned for a later version.",
  },
  {
    q: "How do I uninstall it?",
    a: (
      <>
        Drag Bedrock Launcher from Applications to the Trash. To also remove game versions, profiles, worlds
        and the Google sign-in, delete <code>{DATA}</code>. Back up any worlds you want to keep first.
      </>
    ),
  },
];

export default function Faq() {
  return (
    <Section title="FAQ">
      <Accordion className="max-w-3xl">
        {ITEMS.map((item) => (
          <Accordion.Item key={item.q}>
            <Accordion.Heading>
              <Accordion.Trigger className="font-extrabold">
                {item.q}
                <Accordion.Indicator />
              </Accordion.Trigger>
            </Accordion.Heading>
            <Accordion.Panel>
              <Accordion.Body className="text-muted leading-relaxed">{item.a}</Accordion.Body>
            </Accordion.Panel>
          </Accordion.Item>
        ))}
      </Accordion>
    </Section>
  );
}
