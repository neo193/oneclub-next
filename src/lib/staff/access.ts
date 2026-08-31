import { redirect } from "next/navigation";
import { requireProfile } from "@/lib/auth/profile";
import { canAccessStaffItem, staffNavigation } from "@/lib/staff/navigation";

export async function requireStaffWorkspace(pathname: string) {
  const profile = await requireProfile(pathname);
  const workspace = staffNavigation.find((item) => item.href === pathname);
  if (!workspace || !canAccessStaffItem(profile, workspace)) redirect("/staff");
  return profile;
}
