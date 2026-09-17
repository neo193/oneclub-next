import type { Metadata } from "next";
import { Suspense } from "react";
import { MemberSupportForm } from "@/components/member/support-form";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Member Support",
  description: "Private member concierge and assistance for One Club members.",
  robots: { index: false, follow: false },
};

export default async function MemberSupportPage() {
  const profile = await requireProfile("/portal/support");
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userEmail = String(claimsData?.claims?.email || "");
  const { data: activeTickets, error: ticketsError } = await supabase.rpc("list_my_support_requests");

  return (
    <section className="section member-page">
      <Suspense fallback={<p className="portal-loading">Loading support concierge…</p>}>
        <MemberSupportForm
          profile={profile}
          userEmail={userEmail}
          initialTickets={activeTickets || []}
          ticketsError={ticketsError?.message || ""}
        />
      </Suspense>
    </section>
  );
}

