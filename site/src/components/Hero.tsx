import { BlockButton } from "./BlockButton";
import { DOWNLOAD_URL } from "../site";

export const REQUIREMENTS = "Apple Silicon · macOS 15+ · Signed and notarized · Free and open source";

export function Hero() {
  return (
    <div className="hero-scene relative flex min-h-[70vh] items-center justify-center px-4 py-16">
      <div className="absolute inset-0 bg-[rgb(14_16_20/0.25)]" aria-hidden="true" />
      <div className="block-card relative w-full max-w-xl px-6 py-8 text-center sm:px-10">
        <h1 className="text-4xl font-black tracking-tight sm:text-5xl">Minecraft Bedrock, on your Mac.</h1>
        <p className="mx-auto mt-4 max-w-md text-base leading-relaxed text-[#e6eaef] sm:text-lg">
          Play the Bedrock Edition you own on Google Play, natively on Apple Silicon. Already set up on
          your other Mac? Move your copy across in one file.
        </p>
        <div className="mt-7 flex flex-col justify-center gap-3 sm:flex-row">
          <BlockButton tone="green" href={DOWNLOAD_URL}>
            Download for Mac
          </BlockButton>
          <BlockButton tone="slate" onClick={() => document.getElementById("how")?.scrollIntoView()}>
            How it works
          </BlockButton>
        </div>
        <p className="mt-5 text-xs font-semibold text-[#c3cad4]">{REQUIREMENTS}</p>
      </div>
    </div>
  );
}
