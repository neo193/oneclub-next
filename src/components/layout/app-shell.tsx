"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState, type ReactNode } from "react";

export function AppShell({
  children,
  navigation,
  section,
}: {
  children: ReactNode;
  navigation: { href: string; label: string }[];
  section: string;
}) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);

  return (
    <>
      <header className="site-header">
        <Link className="brand" href={section === "member" ? "/portal" : "/staff"} onClick={() => setOpen(false)}>
          <Image
            src="/assets/oneclub-logo-gold-transparent.png"
            alt="One Club"
            width={136}
            height={68}
            priority
          />
        </Link>
        <nav
          className={open ? "desktop-nav mobile-open" : "desktop-nav"}
          aria-label={`${section} navigation`}
        >
          {navigation.map((item) => {
            const isActive = pathname === item.href;
            return (
              <Link
                href={item.href}
                key={item.href}
                aria-current={isActive ? "page" : undefined}
                onClick={() => setOpen(false)}
              >
                {item.label}
              </Link>
            );
          })}
          <form action="/auth/signout" method="post">
            <button className="nav-signout" type="submit">
              Sign out
            </button>
          </form>
        </nav>
        <button
          className="menu-toggle"
          type="button"
          aria-label={open ? "Close navigation" : "Open navigation"}
          aria-expanded={open}
          onClick={() => setOpen((current) => !current)}
        >
          <span />
          <span />
          <span />
        </button>
      </header>
      <main>{children}</main>
    </>
  );
}

