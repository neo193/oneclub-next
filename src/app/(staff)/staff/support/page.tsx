import type { Metadata } from "next";
import { SupportWorkspace } from "@/components/staff/support-workspace";
import { requireStaffWorkspace } from "@/lib/staff/access";
import { createClient } from "@/lib/supabase/server";
import type { StaffSupportRequest } from "@/types/database";

export const metadata: Metadata = {
  title: "Support Operations",
  description: "Review and update One Club member support requests.",
  robots: { index: false, follow: false },
};

export default async function SupportOperationsPage() {
  await requireStaffWorkspace("/staff/support");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_support_requests_for_staff", { p_status: null });
  return (
    <section className="section staff-page">
      <p className="eyebrow"><span />SUPPORT WORKSPACE</p>
      <h1>Member requests</h1>
      <p className="page-intro">Review member enquiries and keep their operational status current.</p>
      <SupportWorkspace initialRequests={(data || []) as StaffSupportRequest[]} initialError={error ? "Support requests could not be loaded." : ""} />
    </section>
  );
}
