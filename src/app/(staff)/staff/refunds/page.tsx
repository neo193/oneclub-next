import type { Metadata } from "next";
import { RefundsWorkspace } from "@/components/staff/refunds-workspace";
import { requireStaffWorkspace } from "@/lib/staff/access";
import { createClient } from "@/lib/supabase/server";
import type { AdminRefund } from "@/types/database";

export const metadata: Metadata = {
  title: "Refund Operations",
  description: "Administrator event-refund and reconciliation controls.",
  robots: { index: false, follow: false },
};

export default async function RefundOperationsPage() {
  await requireStaffWorkspace("/staff/refunds");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_refunds_for_admin");
  return (
    <section className="section staff-page">
      <p className="eyebrow"><span />ADMINISTRATOR-ONLY FINANCIAL CONTROL</p>
      <h1>Refund operations</h1>
      <p className="page-intro">Issue eligible full event refunds or reconcile refunds already created directly in Razorpay.</p>
      <RefundsWorkspace initialRefunds={(data || []) as AdminRefund[]} initialError={error ? "Refund records could not be loaded." : ""} />
    </section>
  );
}
