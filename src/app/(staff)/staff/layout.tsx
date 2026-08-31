import type { ReactNode } from "react";
import { AppShell } from "@/components/layout/app-shell";
import { redirect } from "next/navigation";
import { requireProfile } from "@/lib/auth/profile";

const navigation = [
  { href: "/staff", label: "Overview" },
  { href: "/staff/members", label: "Members" },
  { href: "/staff/events", label: "Events" },
  { href: "/staff/partners", label: "Partners & Benefits" },
];

export default async function StaffLayout({ children }: { children: ReactNode }) {
  const profile = await requireProfile("/staff");
  if (!['staff','admin'].includes(profile.app_role)) redirect('/portal');
  return <AppShell navigation={navigation} section="staff">{children}</AppShell>;
}
