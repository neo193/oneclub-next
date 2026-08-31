import type { ReactNode } from "react";
import { classes } from "@/lib/utils/classes";

export function ContentGrid({ children }: { children: ReactNode }) {
  return <section className="section content-grid">{children}</section>;
}

export function ContentPanel({ children, wide = false }: { children: ReactNode; wide?: boolean }) {
  return <article className={classes("content-panel", wide && "wide")}>{children}</article>;
}

