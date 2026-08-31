import type { ReactNode } from "react";
import { AppShell } from "@/components/layout/app-shell";
import { redirect } from "next/navigation";
import { requireProfile } from "@/lib/auth/profile";
import { navigationForProfile } from "@/lib/staff/navigation";
import "./staff.css";

export default async function StaffLayout({ children }: { children: ReactNode }) {
  const profile = await requireProfile("/staff");
  if (!['staff','admin'].includes(profile.app_role)) redirect('/portal');
  const navigation = navigationForProfile(profile).map(({ href, label }) => ({ href, label }));
  return <AppShell navigation={navigation} section="staff">{children}</AppShell>;
}
