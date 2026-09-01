"use client";

import { useState } from "react";
import { ConfirmationDialog } from "@/components/ui/confirmation-dialog";
import { createClient } from "@/lib/supabase/client";
import { callRazorpayService } from "@/lib/payments/razorpay";
import type { AdminRefund } from "@/types/database";

const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR" }).format(paise / 100);
const friendly = (value: string | null) => String(value || "requested").replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());

export function RefundsWorkspace({ initialRefunds, initialError }: { initialRefunds: AdminRefund[]; initialError: string }) {
  const [refunds, setRefunds] = useState(initialRefunds);
  const [message, setMessage] = useState(initialError || `${initialRefunds.filter((row) => row.refund_status !== "processed").length} refunds require attention.`);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [issueTarget, setIssueTarget] = useState<AdminRefund | null>(null);

  async function load() {
    const supabase = createClient();
    const { data, error } = await supabase.rpc("list_refunds_for_admin");
    if (error) throw new Error(error.message);
    setRefunds(data || []);
  }

  async function run(refund: AdminRefund, action: "refund_issue" | "refund_reconcile") {
    setPendingId(refund.booking_id);
    setMessage(action === "refund_issue" ? "Issuing the full refund securely…" : "Checking Razorpay for an existing refund…");
    try {
      const result = await callRazorpayService({ action, booking_id: refund.booking_id });
      setMessage(action === "refund_reconcile" && !result.reconciled ? "No matching full refund was found in Razorpay." : `Refund ${friendly(String(result.status || "pending"))}. Reference: ${String(result.refund_id || "pending")}`);
      await load(); setIssueTarget(null);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Refund operation failed.");
    } finally { setPendingId(null); }
  }

  return (
    <div className="staff-workspace">
      <div className="staff-toolbar"><div><strong>Refund queue</strong><p>Processed refunds remain visible for verification and audit history.</p></div><button className="button button-secondary" type="button" onClick={() => load().catch((error) => setMessage(error.message))}>Refresh</button></div>
      <p className="form-message" aria-live="polite">{message}</p>
      <div className="refund-list-next">
        {refunds.length === 0 ? <p className="staff-empty">No cancelled paid bookings require a refund.</p> : refunds.map((refund) => (
          <article className="refund-card-next" key={refund.booking_id}>
            <div><p className="eyebrow compact">{friendly(refund.refund_status)}</p><h2>{refund.event_title}</h2><p>{refund.member_name || refund.member_email} · {refund.member_number || "No member ID"}</p></div>
            <dl>
              <div><dt>Amount</dt><dd>{money(refund.amount_paise)}</dd></div>
              <div><dt>Payment ID</dt><dd>{refund.razorpay_payment_id}</dd></div>
              <div><dt>Refund ID</dt><dd>{refund.razorpay_refund_id || "Not recorded"}</dd></div>
              <div><dt>Cancelled</dt><dd>{refund.cancelled_at ? new Date(refund.cancelled_at).toLocaleString("en-IN") : "—"}</dd></div>
            </dl>
            <div className="refund-actions-next">
              {refund.refund_status !== "processed" ? <><button className="button button-secondary" type="button" disabled={pendingId === refund.booking_id} onClick={() => run(refund, "refund_reconcile")}>Reconcile</button><button className="button button-danger" type="button" disabled={pendingId === refund.booking_id} onClick={() => setIssueTarget(refund)}>Issue full refund</button></> : <span className="staff-status staff-status-approved">Refund complete</span>}
            </div>
          </article>
        ))}
      </div>
      <p className="staff-security-note">Refunds are irreversible. Confirm the member, event, payment ID and amount before issuing one.</p>
      <ConfirmationDialog open={Boolean(issueTarget)} title="Issue this full refund?" confirmLabel={`Refund ${issueTarget ? money(issueTarget.amount_paise) : ""}`} cancelLabel="Keep payment" pendingLabel="Issuing refund…" pending={Boolean(pendingId)} onClose={() => setIssueTarget(null)} onConfirm={() => issueTarget && run(issueTarget, "refund_issue")}>
        <p>You are about to refund <strong>{issueTarget ? money(issueTarget.amount_paise) : ""}</strong> to {issueTarget?.member_name || issueTarget?.member_email} for “{issueTarget?.event_title}”.</p><p>This financial action is irreversible and will be recorded in the audit trail.</p>
      </ConfirmationDialog>
    </div>
  );
}
