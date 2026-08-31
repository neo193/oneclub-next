import type { Metadata } from "next";
import { AdminOverview } from "@/components/staff/admin-overview";
import { requireStaffWorkspace } from "@/lib/staff/access";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Administrator Overview",
  description: "Read-only One Club business and operational indicators.",
  robots: { index: false, follow: false },
};

export default async function AdministratorOverviewPage() {
  await requireStaffWorkspace("/staff/overview");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("get_technical_diagnostics");
  return (
    <section className="section staff-page">
      <p className="eyebrow"><span />BUSINESS OVERVIEW</p>
      <h1>Administrator overview</h1>
      <p className="page-intro">A read-only snapshot of membership, sales, support, events, payments and member content.</p>
      <AdminOverview initialData={data} initialError={error ? "The business overview could not be loaded." : ""} />
    </section>
  );
}
