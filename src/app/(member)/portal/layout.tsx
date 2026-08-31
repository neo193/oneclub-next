import type { ReactNode } from "react";
import "./member.css";
import { AppShell } from "@/components/layout/app-shell";
import { redirect } from "next/navigation";
import { requireProfile } from "@/lib/auth/profile";

const navigation = [
  { href: "/portal", label: "My Portal" },
  { href: "/portal/benefits", label: "Benefits" },
  { href: "/portal/events", label: "Events" },
  { href: "/portal/profile", label: "Profile" },
  { href: "/portal/support", label: "Support" },
];

export default async function MemberLayout({ children }: { children: ReactNode }) {
  const profile = await requireProfile("/portal");
  if (profile.app_role !== "member") redirect("/staff");
  return <AppShell navigation={navigation} section="member">{children}</AppShell>;
}
