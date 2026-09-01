import type { Metadata } from "next";
import { BenefitsCatalogue } from "@/components/member/benefits-catalogue";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";
import type { MemberBenefitCatalogueItem } from "@/types/database";

export const metadata: Metadata = {
  title: "Member Benefits",
  description: "Exclusive privileges and partner offers for One Club members.",
  robots: { index: false, follow: false },
};

export default async function MemberBenefitsPage() {
  const profile = await requireProfile("/portal/benefits");
  if (profile.membership_state !== "active") {
    return (
      <section className="section member-page">
        <p className="eyebrow"><span />MEMBER-ONLY PRIVILEGES</p>
        <h1>Member Benefits</h1>
        <p className="access-message">An active membership is required to access partner privileges. Visit My Portal for information about your membership status.</p>
      </section>
    );
  }
  const supabase = await createClient();

  const catalogue = await supabase.rpc("get_active_member_benefit_catalogue");
  const fallback = catalogue.error ? await supabase.rpc("get_active_member_benefits") : null;
  const error = catalogue.error && fallback?.error ? fallback.error : null;
  const benefits: MemberBenefitCatalogueItem[] = catalogue.error
    ? (fallback?.data || []).map((item) => ({ ...item, locations: [] }))
    : catalogue.data || [];

  return (
    <section className="section member-page">
      <p className="eyebrow">
        <span />
        MEMBER-ONLY PRIVILEGES
      </p>
      <h1>Member Benefits</h1>
      <p className="page-intro">
        A private catalogue of privileges curated exclusively for active One Club members across hospitality, wellness, lifestyle, and automotive partners.
      </p>

      {error ? (
        <p className="access-message" role="alert">We could not load member benefits. Please refresh the page or contact Member Support if the problem continues. Technical detail: {error.message}</p>
      ) : (
        <BenefitsCatalogue benefits={benefits} />
      )}
    </section>
  );
}

