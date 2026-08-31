import type { ReactNode } from "react";

export function PageHero({ eyebrow, title, children }: { eyebrow: string; title: ReactNode; children: ReactNode }) {
  return <section className="section page-hero"><p className="eyebrow"><span />{eyebrow}</p><h1>{title}</h1><div className="page-intro">{children}</div></section>;
}

