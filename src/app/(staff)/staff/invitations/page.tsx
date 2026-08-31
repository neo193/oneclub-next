import type { Metadata } from "next";
import { InvitationsWorkspace } from "@/components/staff/invitations-workspace";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";
import type { StaffEnquiry } from "@/types/database";

export const metadata: Metadata = {
  title: "Invitation Operations",
  description: "Review One Club enquiries and issue approved membership invitations.",
  robots: { index: false, follow: false },
};

export default async function InvitationsPage() {
  await requireProfile("/staff/invitations");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_enquiries_for_staff");
  return (
    <section className="section staff-page">
      <p className="eyebrow"><span />INVITATION OPERATIONS</p>
      <h1>Enquiries &amp;<br /><em>approvals.</em></h1>
      <p className="page-intro">Review membership enquiries and generate a secure invitation link after approval.</p>
      <InvitationsWorkspace
        initialEnquiries={(data || []) as StaffEnquiry[]}
        initialError={error ? "Enquiries could not be loaded. Please retry." : ""}
      />
    </section>
  );
}
