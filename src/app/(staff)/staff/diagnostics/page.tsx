import type { Metadata } from "next";
import { TechnicalDiagnosticsWorkspace } from "@/components/staff/technical-diagnostics-workspace";
import { requireStaffWorkspace } from "@/lib/staff/access";

export const metadata: Metadata = {
  title: "Technical Diagnostics",
  description: "Read-only One Club service, deployment, security and data-integrity checks.",
  robots: { index: false, follow: false },
};

export default async function TechnicalDiagnosticsPage() {
  await requireStaffWorkspace("/staff/diagnostics");
  return (
    <section className="section staff-page">
      <p className="eyebrow"><span />READ-ONLY SYSTEM VIEW</p>
      <h1>Technical diagnostics</h1>
      <p className="page-intro">Live checks for application delivery, Supabase, payments, deployments, security and data integrity.</p>
      <TechnicalDiagnosticsWorkspace />
    </section>
  );
}
