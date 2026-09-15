"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import { ConfirmationDialog } from "@/components/ui/confirmation-dialog";
import type { StaffEnquiry } from "@/types/database";

function formatDate(value: string) {
  return new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}

export function InvitationsWorkspace({
  initialEnquiries,
  initialError,
}: {
  initialEnquiries: StaffEnquiry[];
  initialError: string;
}) {
  const [enquiries, setEnquiries] = useState(initialEnquiries);
  const [message, setMessage] = useState(initialError || `${initialEnquiries.length} enquiries loaded.`);
  const [pendingId, setPendingId] = useState<string | null>(null);
  const [invitationLinks, setInvitationLinks] = useState<Record<string, string>>({});
  const [menuId, setMenuId] = useState<string | null>(null);
  const [rejectTarget, setRejectTarget] = useState<StaffEnquiry | null>(null);

  async function load() {
    setMessage("Refreshing enquiries…");
    const supabase = createClient();
    const { data, error } = await supabase.rpc("list_enquiries_for_staff");
    if (error) throw new Error(error.message);
    setEnquiries(data || []);
    setMessage(`${data?.length || 0} enquiries loaded.`);
  }

  async function approve(enquiry: StaffEnquiry) {
    setPendingId(enquiry.id);
    setMessage(`Generating an invitation for ${enquiry.full_name}…`);
    try {
      const supabase = createClient();
      const { data: token, error } = await supabase.rpc("approve_enquiry_and_create_invitation", { p_enquiry_id: enquiry.id });
      if (error || !token) throw new Error(error?.message || "Invitation token was not returned.");
      const url = new URL("/membership-invite", window.location.origin);
      url.searchParams.set("token", token);
      setInvitationLinks((links) => ({ ...links, [enquiry.id]: url.href }));
      setEnquiries((rows) => rows.map((row) => row.id === enquiry.id ? { ...row, status: "approved" } : row));
      setMessage("Invitation generated. Copy the secure link and send it to the approved email address.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Invitation could not be generated.");
    } finally {
      setPendingId(null);
    }
  }

  async function copyLink(id: string) {
    const link = invitationLinks[id];
    if (!link) return;
    await navigator.clipboard.writeText(link);
    setMessage("Invitation link copied.");
  }

  async function reissueAndCopy(enquiry: StaffEnquiry) {
    setMenuId(null);
    setPendingId(enquiry.id);
    setMessage(`Creating a fresh approval link for ${enquiry.full_name}…`);
    try {
      const supabase = createClient();
      const { data: token, error } = await supabase.rpc("reissue_enquiry_invitation", { p_enquiry_id: enquiry.id });
      if (error || !token) throw new Error(error?.message || "Invitation token was not returned.");
      const url = new URL("/membership-invite", window.location.origin);
      url.searchParams.set("token", token);
      await navigator.clipboard.writeText(url.href);
      setInvitationLinks((links) => ({ ...links, [enquiry.id]: url.href }));
      setMessage("A fresh approval link was copied. Any earlier unused link has been replaced.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "The approval link could not be copied.");
    } finally {
      setPendingId(null);
    }
  }

  async function reject() {
    if (!rejectTarget) return;
    const enquiry = rejectTarget;
    setPendingId(enquiry.id);
    setMessage(`Rejecting the enquiry from ${enquiry.full_name}…`);
    try {
      const supabase = createClient();
      const { error } = await supabase.rpc("reject_enquiry", { p_enquiry_id: enquiry.id });
      if (error) throw new Error(error.message);
      setEnquiries((rows) => rows.map((row) => row.id === enquiry.id ? { ...row, status: "rejected" } : row));
      setInvitationLinks((links) => {
        const next = { ...links };
        delete next[enquiry.id];
        return next;
      });
      setRejectTarget(null);
      setMenuId(null);
      setMessage(`The enquiry from ${enquiry.full_name} was rejected.`);
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "The enquiry could not be rejected.");
    } finally {
      setPendingId(null);
    }
  }

  return (
    <div className="staff-workspace">
      <div className="staff-toolbar">
        <p className="form-message" aria-live="polite">{message}</p>
        <button className="button button-secondary" type="button" onClick={() => load().catch((error) => setMessage(error.message))}>Refresh</button>
      </div>
      <div className="enquiry-list">
        {enquiries.length === 0 ? <p className="staff-empty">No membership enquiries are currently waiting.</p> : enquiries.map((enquiry) => (
          <article className="enquiry-card" key={enquiry.id}>
            {enquiry.status === "approved" && (
              <div
                className="enquiry-menu"
                onBlur={(event) => {
                  if (!event.currentTarget.contains(event.relatedTarget as Node | null)) setMenuId(null);
                }}
              >
                <button
                  className="enquiry-menu-trigger"
                  type="button"
                  aria-label={`Actions for ${enquiry.full_name}`}
                  aria-haspopup="menu"
                  aria-expanded={menuId === enquiry.id}
                  disabled={pendingId === enquiry.id}
                  onClick={() => setMenuId((current) => current === enquiry.id ? null : enquiry.id)}
                  onKeyDown={(event) => { if (event.key === "Escape") setMenuId(null); }}
                >
                  ⋯
                </button>
                {menuId === enquiry.id && (
                  <div className="enquiry-menu-popover" role="menu">
                    <button type="button" role="menuitem" onClick={() => reissueAndCopy(enquiry)}>Copy approval link</button>
                  </div>
                )}
              </div>
            )}
            <div>
              <span className={`staff-status staff-status-${enquiry.status}`}>{enquiry.status}</span>
              <h2>{enquiry.full_name}</h2>
              <p>{enquiry.email} · {enquiry.phone}</p>
              {enquiry.created_at && <small>Received {formatDate(enquiry.created_at)}</small>}
            </div>
            {(enquiry.status === "new" || enquiry.status === "contacted") && (
              <div className="enquiry-actions">
                <button className="button button-primary" type="button" disabled={pendingId === enquiry.id} onClick={() => approve(enquiry)}>
                  {pendingId === enquiry.id ? "Generating…" : "Approve & generate link"}
                </button>
                <button className="button button-danger" type="button" disabled={pendingId === enquiry.id} onClick={() => setRejectTarget(enquiry)}>
                  Reject enquiry
                </button>
              </div>
            )}
            {invitationLinks[enquiry.id] && (
              <div className="invitation-output">
                <input readOnly value={invitationLinks[enquiry.id]} aria-label={`Invitation link for ${enquiry.full_name}`} />
                <button className="button button-secondary" type="button" onClick={() => copyLink(enquiry.id)}>Copy link</button>
              </div>
            )}
          </article>
        ))}
      </div>
      <ConfirmationDialog
        open={Boolean(rejectTarget)}
        title="Reject this enquiry?"
        confirmLabel="Reject enquiry"
        pendingLabel="Rejecting…"
        pending={Boolean(pendingId)}
        onClose={() => !pendingId && setRejectTarget(null)}
        onConfirm={reject}
      >
        <p>You are about to reject the enquiry from {rejectTarget?.full_name}.</p>
        <p>The enquiry will be marked rejected and the decision will be recorded in the staff audit trail.</p>
      </ConfirmationDialog>
    </div>
  );
}

