import type { ReactNode } from "react";
import { AppShell } from "@/components/layout/app-shell";

const navigation = [
  { href: "/portal", label: "My Portal" },
  { href: "/portal/events", label: "Events" },
  { href: "/portal/benefits", label: "Benefits" },
  { href: "/portal/support", label: "Support" },
];

export default function MemberLayout({ children }: { children: ReactNode }) {
  return <AppShell navigation={navigation} section="member">{children}</AppShell>;
}

