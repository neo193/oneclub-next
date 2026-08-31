import Link from "next/link";
import type { ReactNode } from "react";

export function AppShell({ children, navigation, section }: { children: ReactNode; navigation: { href: string; label: string }[]; section: string }) {
  return <><header className="site-header"><Link className="text-brand" href="/">One Club</Link><nav className="desktop-nav" aria-label={`${section} navigation`}>{navigation.map((item) => <Link href={item.href} key={item.href}>{item.label}</Link>)}<form action="/auth/signout" method="post"><button className="nav-signout" type="submit">Sign out</button></form></nav></header><main>{children}</main></>;
}
