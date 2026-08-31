import type { Profile } from "@/types/database";

export type StaffNavigationItem = {
  href: string;
  label: string;
  description: string;
  adminOnly?: boolean;
  staffRoles?: NonNullable<Profile["staff_role"]>[];
  available?: boolean;
};

export const staffNavigation: StaffNavigationItem[] = [
  { href: "/staff", label: "Workspace", description: "Your authorised operational tools.", available: true },
  { href: "/staff/overview", label: "Overview", description: "Business and operational indicators.", adminOnly: true, available: true },
  { href: "/staff/refunds", label: "Refunds", description: "Event refund and reconciliation controls.", adminOnly: true, available: true },
  { href: "/staff/invitations", label: "Invitations", description: "Review enquiries and generate membership invitations.", staffRoles: ["technical", "marketing", "general"], available: true },
  { href: "/staff/members", label: "Members", description: "Profiles, membership controls and audit history.", staffRoles: ["general"] },
  { href: "/staff/support", label: "Support", description: "Review and update member support requests.", staffRoles: ["general"], available: true },
  { href: "/staff/partners", label: "Partners & Benefits", description: "Partner, benefit and property content.", staffRoles: ["general"] },
  { href: "/staff/events", label: "Events", description: "Event catalogue, capacity and complimentary bookings.", staffRoles: ["marketing"] },
  { href: "/staff/diagnostics", label: "Diagnostics", description: "Read-only technical and data-integrity checks.", staffRoles: ["technical"], available: true },
];

export function canAccessStaffItem(profile: Pick<Profile, "app_role" | "staff_role">, item: StaffNavigationItem) {
  if (profile.app_role === "admin") return true;
  if (profile.app_role !== "staff" || item.adminOnly) return false;
  if (!item.staffRoles) return true;
  return Boolean(profile.staff_role && item.staffRoles.includes(profile.staff_role));
}

export function navigationForProfile(profile: Pick<Profile, "app_role" | "staff_role">) {
  return staffNavigation.filter((item) => item.available && canAccessStaffItem(profile, item));
}
