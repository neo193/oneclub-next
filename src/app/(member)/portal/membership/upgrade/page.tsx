import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { MembershipPayment } from "@/components/member/membership-payment";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Upgrade Membership", robots: { index: false, follow: false } };

export default async function UpgradeMembershipPage() {
  const profile = await requireProfile("/portal/membership/upgrade");
  if (profile.membership_state !== "active") redirect("/portal");
  const supabase = await createClient();
  const [{ data: options, error }, { data: claims }] = await Promise.all([
    supabase.rpc("get_eligible_membership_upgrades"), supabase.auth.getClaims(),
  ]);
  if (error) throw new Error(error.message);
  if (!options?.length) redirect("/portal");
  return <section className="section member-page"><p className="eyebrow"><span />MEMBERSHIP UPGRADE</p><h1>Choose your next tier.</h1><p className="page-intro">Your current active-term payment may be credited when the selected tier permits it. Previous membership terms do not accumulate toward this upgrade.</p><MembershipPayment email={String(claims?.claims?.email || "")} tiers={options} mode="upgrade" /></section>;
}
