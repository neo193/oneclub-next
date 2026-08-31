import type { ReactNode } from "react";
import { AppShell } from "@/components/layout/app-shell";

const navigation = [
  { href: "/membership", label: "Membership" },
  { href: "/events", label: "Events" },
  { href: "/partners", label: "Partners & Benefits" },
  { href: "/contact", label: "Contact" },
];

export default function PublicLayout({ children }: { children: ReactNode }) {
  return <AppShell navigation={navigation} section="public">{children}</AppShell>;
}

