import type { ReactNode } from "react";
import { Link } from "react-router-dom";

type Props = {
  tone: "green" | "slate";
  href?: string;
  to?: string;
  onClick?: () => void;
  children: ReactNode;
  className?: string;
};

/** A link drawn like the launcher's 3D buttons: a face, a dark bottom edge and a light top edge. */
export function BlockButton({ tone, href, to, onClick, children, className = "" }: Props) {
  const cls = `block-btn block-btn-${tone} ${className}`;
  if (onClick) {
    return (
      <button type="button" onClick={onClick} className={cls}>
        {children}
      </button>
    );
  }
  if (to) {
    return (
      <Link to={to} className={cls}>
        {children}
      </Link>
    );
  }
  const external = href?.startsWith("http");
  return (
    <a href={href} className={cls} {...(external ? { target: "_blank", rel: "noopener noreferrer" } : {})}>
      {children}
    </a>
  );
}
