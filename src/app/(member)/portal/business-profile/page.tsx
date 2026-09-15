import type { Metadata } from "next";
import { redirect } from "next/navigation";
import { BusinessProfileEditor } from "@/components/member/business-profile-editor";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Business Profile", robots: { index: false, follow: false } };

export default async function BusinessProfilePage() {
  const member = await requireProfile("/portal/business-profile");
  if (member.membership_state !== "active") redirect("/portal");
  const { data, error } = await (await createClient()).rpc("get_my_business_profile");
  if (error) throw new Error(error.message);
  return <section className="section member-page"><p className="eyebrow"><span />BUSINESS NETWORK</p><h1>Your business profile.</h1><p className="page-intro">Choose what you share with the private member directory. Personal account details are never included.</p><BusinessProfileEditor profile={data} /></section>;
}
