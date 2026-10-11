import type { ReactNode } from "react";

type Props = { id?: string; title?: string; intro?: ReactNode; children: ReactNode; className?: string };

/** A centered block of page content with an optional heading. */
export function Section({ id, title, intro, children, className = "" }: Props) {
  return (
    <section id={id} className={`mx-auto w-full max-w-6xl px-4 py-12 ${className}`}>
      {title && <h2 className="text-3xl font-black tracking-tight">{title}</h2>}
      {intro && <p className="mt-3 max-w-2xl text-muted">{intro}</p>}
      <div className={title || intro ? "mt-8" : ""}>{children}</div>
    </section>
  );
}
