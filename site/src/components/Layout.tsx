import { useEffect } from "react";
import { NavLink, Outlet, useLocation } from "react-router-dom";
import { Button, Drawer, Tooltip, useOverlayState } from "@heroui/react";
import { Menu, Moon, Sun, X } from "lucide-react";
import { useTheme } from "../theme";
import { LICENSE_URL, NAV, REPO, asset } from "../site";

function GithubMark({ size = 20 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82a7.6 7.6 0 0 1 4 0c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

const linkClass = ({ isActive }: { isActive: boolean }) =>
  `px-3 py-2 text-sm font-extrabold hover:text-foreground ${isActive ? "text-foreground" : "text-muted"}`;

function ThemeButton() {
  const [theme, toggle] = useTheme();
  const label = theme === "dark" ? "Light mode" : "Dark mode";
  return (
    <Tooltip delay={300}>
      <Button isIconOnly variant="ghost" onPress={toggle} aria-label={label}>
        {theme === "dark" ? <Sun size={18} aria-hidden="true" /> : <Moon size={18} aria-hidden="true" />}
      </Button>
      <Tooltip.Content>{label}</Tooltip.Content>
    </Tooltip>
  );
}

function MobileMenu() {
  const state = useOverlayState();
  const { pathname } = useLocation();
  useEffect(() => {
    state.close();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [pathname]);
  return (
    <Drawer state={state}>
      <Button isIconOnly variant="ghost" className="md:hidden" onPress={state.open} aria-label="Open menu">
        <Menu size={20} aria-hidden="true" />
      </Button>
      <Drawer.Backdrop>
        <Drawer.Content placement="right">
          <Drawer.Dialog aria-label="Site menu">
            <Drawer.Header>
              <Drawer.Heading>Menu</Drawer.Heading>
              <Button isIconOnly variant="ghost" onPress={state.close} aria-label="Close menu">
                <X size={18} aria-hidden="true" />
              </Button>
            </Drawer.Header>
            <Drawer.Body>
              <nav aria-label="Main" className="flex flex-col gap-1">
                {NAV.map((n) => (
                  <NavLink key={n.to} to={n.to} end={n.end} className={linkClass} onClick={state.close}>
                    {n.label}
                  </NavLink>
                ))}
                <a className="px-3 py-2 text-sm font-extrabold text-muted hover:text-foreground" href={REPO} target="_blank" rel="noopener noreferrer">
                  GitHub
                </a>
              </nav>
            </Drawer.Body>
          </Drawer.Dialog>
        </Drawer.Content>
      </Drawer.Backdrop>
    </Drawer>
  );
}

export default function Layout() {
  const { pathname } = useLocation();
  useEffect(() => {
    window.scrollTo(0, 0);
    document.getElementById("main")?.focus({ preventScroll: true });
  }, [pathname]);

  return (
    <div className="flex min-h-screen flex-col">
      <a href="#main" className="skip-link" onClick={(e) => { e.preventDefault(); document.getElementById("main")?.focus(); }}>
        Skip to content
      </a>
      <header className="sticky top-0 z-40 border-b-2 border-[var(--bl-edge)] bg-[var(--bl-bar)] text-white">
        <div className="mx-auto flex h-14 max-w-6xl items-center justify-between gap-4 px-4">
          <NavLink to="/" aria-label="Bedrock Launcher, home" className="flex items-center gap-2 font-black">
            <img src={asset("icon.png")} alt="" width={28} height={28} className="pixel" />
            <span>Bedrock Launcher</span>
          </NavLink>
          <nav aria-label="Main" className="hidden items-center md:flex">
            {NAV.map((n) => (
              <NavLink key={n.to} to={n.to} end={n.end} className={({ isActive }) => `px-3 py-2 text-sm font-extrabold hover:text-white ${isActive ? "text-white" : "text-[var(--bl-dim)]"}`}>
                {n.label}
              </NavLink>
            ))}
          </nav>
          <div className="dark flex items-center gap-1">
            <Tooltip delay={300}>
              <Tooltip.Trigger>
                <a
                  href={REPO}
                  target="_blank"
                  rel="noopener noreferrer"
                  aria-label="GitHub repository (opens in a new tab)"
                  className="hidden h-10 w-10 items-center justify-center text-white hover:text-[var(--bl-green-light)] sm:inline-flex"
                >
                  <GithubMark />
                </a>
              </Tooltip.Trigger>
              <Tooltip.Content>GitHub</Tooltip.Content>
            </Tooltip>
            <ThemeButton />
            <MobileMenu />
          </div>
        </div>
      </header>

      <main id="main" tabIndex={-1} className="flex-1 outline-none">
        <Outlet />
      </main>

      <footer className="border-t-2 border-[var(--bl-edge)] bg-[var(--bl-bar)] text-[var(--bl-dim)]">
        <div className="mx-auto flex max-w-6xl flex-col gap-3 px-4 py-8 text-sm md:flex-row md:items-center md:justify-between">
          <p>
            Free software under the{" "}
            <a className="text-white underline underline-offset-4" href={LICENSE_URL} target="_blank" rel="noopener noreferrer">
              GPL-3.0
            </a>
            . Source on{" "}
            <a className="text-white underline underline-offset-4" href={REPO} target="_blank" rel="noopener noreferrer">
              GitHub
            </a>
            .
          </p>
          <p>Not an official Minecraft product. Not approved by or associated with Mojang or Microsoft.</p>
        </div>
      </footer>
    </div>
  );
}
