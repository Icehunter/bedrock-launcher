export const REPO = "https://github.com/Icehunter/bedrock-launcher";
export const DOWNLOAD_URL = `${REPO}/releases/latest`;
export const RELEASES_URL = `${REPO}/releases`;
export const LICENSE_URL = `${REPO}/blob/main/LICENSE`;

export const NAV: { to: string; label: string; end?: boolean }[] = [
  { to: "/", label: "Home", end: true },
  { to: "/install", label: "Install" },
  { to: "/guide", label: "Guide" },
  { to: "/faq", label: "FAQ" },
  { to: "/releases", label: "Releases" },
];

/** A file in public/, with the site's base path in front. */
export const asset = (path: string) => `${import.meta.env.BASE_URL}${path}`;
