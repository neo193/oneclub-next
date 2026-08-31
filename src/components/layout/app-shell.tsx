import Link from "next/link";
import type { ReactNode } from "react";

type NavigationItem = {
  href: string;
  label: string;
};

type AppShellProps = {
  children: ReactNode;
  navigation: NavigationItem[];
  section: "public" | "member" | "staff";
};

export function AppShell({ children, navigation, section }: AppShellProps) {
  return (
    <>
      <header className="site-header">
        <Link className="brand" href="/" aria-label="One Club home">
          <span className="brand-monogram">OC</span>
          <span>One Club</span>
        </Link>
        <nav aria-label={`${section} navigation`}>
          {navigation.map((item) => (
            <Link href={item.href} key={item.href}>
              {item.label}
            </Link>
          ))}
        </nav>
      </header>
      <main>{children}</main>
    </>
  );
}

