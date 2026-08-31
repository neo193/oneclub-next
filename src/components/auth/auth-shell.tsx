import Image from "next/image";
import Link from "next/link";
import type { ReactNode } from "react";

export function AuthShell({ eyebrow, title, description, children, returnHref = "/", returnLabel = "Return to website" }: { eyebrow: string; title: ReactNode; description: string; children: ReactNode; returnHref?: string; returnLabel?: string }) {
  return <><header className="site-header auth-header"><Link className="brand" href="/" aria-label="One Club home"><Image src="/assets/oneclub-logo-gold-transparent.png" alt="One Club" width={136} height={68} priority /></Link><Link className="nav-cta" href={returnHref}>{returnLabel}</Link></header><main className="auth-layout"><section className="auth-intro"><p className="eyebrow"><span />{eyebrow}</p><h1>{title}</h1><p>{description}</p></section>{children}</main></>;
}
