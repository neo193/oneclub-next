"use client";

import Image from "next/image";
import Link from "next/link";
import { usePathname } from "next/navigation";
import { useState } from "react";

const navigation = [
  { href: "/about", label: "About" },
  { href: "/membership", label: "Membership" },
  { href: "/benefits", label: "Benefits" },
  { href: "/partners", label: "Partners" },
  { href: "/events", label: "Events" },
  { href: "/contact", label: "Contact" },
];

export function PublicHeader() {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const legacyLogin = `${process.env.NEXT_PUBLIC_LEGACY_SITE_URL ?? "https://dev.oneclub.net.in"}/login.html`;

  return (
    <header className="site-header">
      <Link className="brand" href="/" aria-label="One Club home" onClick={() => setOpen(false)}>
        <Image src="/assets/oneclub-logo-gold-transparent.png" alt="One Club" width={136} height={68} priority />
      </Link>
      <nav className={open ? "desktop-nav mobile-open" : "desktop-nav"} aria-label="Primary navigation">
        {navigation.map((item) => (
          <Link href={item.href} key={item.href} aria-current={pathname === item.href ? "page" : undefined} onClick={() => setOpen(false)}>{item.label}</Link>
        ))}
        <a href={legacyLogin} onClick={() => setOpen(false)}>Member Login</a>
        <Link className="nav-cta" href="/contact" onClick={() => setOpen(false)}>Request an Enquiry</Link>
      </nav>
      <button className="menu-toggle" type="button" aria-label={open ? "Close navigation" : "Open navigation"} aria-expanded={open} onClick={() => setOpen((current) => !current)}>
        <span /><span /><span />
      </button>
    </header>
  );
}

