import type { ReactNode } from "react";
import { AppShell } from "@/components/layout/app-shell";

const navigation = [
  { href: "/staff", label: "Overview" },
  { href: "/staff/members", label: "Members" },
  { href: "/staff/events", label: "Events" },
  { href: "/staff/partners", label: "Partners & Benefits" },
];

export default function StaffLayout({ children }: { children: ReactNode }) {
  return <AppShell navigation={navigation} section="staff">{children}</AppShell>;
}

