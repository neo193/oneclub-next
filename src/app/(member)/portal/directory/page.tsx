import type { Metadata } from "next";
import { Button } from "@/components/ui/button";
import { BusinessDirectory } from "@/components/member/business-directory";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = { title: "Business Directory", robots: { index: false, follow: false } };

export default async function DirectoryPage() {
  const member = await requireProfile("/portal/directory");
  const supabase = await createClient();
  const { data: ownProfile } = await supabase.rpc("get_my_business_profile");
  const enabled = member.membership_state === "active" && ownProfile?.status === "published";
  const { data: results } = enabled ? await supabase.rpc("search_business_directory", { p_limit: 30 }) : { data: [] };
  return <section className="section member-page"><p className="eyebrow"><span />PRIVATE MEMBER NETWORK</p><h1>Business directory.</h1><p className="page-intro">Discover members by industry, role and shared business interests.</p>{enabled ? <><div className="directory-heading-action"><p>Your published profile gives you access to the directory.</p><Button href="/portal/business-profile" variant="secondary">Edit my business profile</Button></div><BusinessDirectory initialResults={results || []} /></> : <aside className="portal-support-card directory-gate"><div><p className="eyebrow compact">OPT-IN DIRECTORY</p><h2>Create your business profile to enter.</h2><p>Directory access is reciprocal: only active members who publish a business profile can discover other participating members.</p></div><Button href="/portal/business-profile" variant="primary">Create business profile</Button></aside>}</section>;
}
