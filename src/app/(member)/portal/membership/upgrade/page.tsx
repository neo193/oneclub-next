import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { MembershipPayment } from "@/components/member/membership-payment";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Upgrade to Founding Membership", robots: { index: false, follow: false } };

export default async function UpgradeMembershipPage() {
  const profile = await requireProfile("/portal/membership/upgrade");
  if (profile.membership_state !== "active" || profile.membership_plan !== "annual") redirect("/portal");
  const supabase = await createClient();
  const [{ data: options, error }, { data: claims }] = await Promise.all([
    supabase.rpc("get_membership_purchase_options"), supabase.auth.getClaims(),
  ]);
  if (error || !options) throw new Error(error?.message || "Upgrade details are unavailable");
  return <section className="section member-page"><p className="eyebrow"><span />LIMITED FOUNDING TIER</p><h1>Membership for a lifetime.</h1><p className="page-intro">Your current annual-term payment is credited once. Previous annual terms do not accumulate toward this upgrade.</p><MembershipPayment email={String(claims?.claims?.email || "")} options={options} /></section>;
}

