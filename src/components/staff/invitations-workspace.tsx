"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
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
    await navigator.clipboard.writeText(invitationLinks[id]);
    setMessage("Invitation link copied.");
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
            <div>
              <span className={`staff-status staff-status-${enquiry.status}`}>{enquiry.status}</span>
              <h2>{enquiry.full_name}</h2>
              <p>{enquiry.email} · {enquiry.phone}</p>
              {enquiry.created_at && <small>Received {formatDate(enquiry.created_at)}</small>}
            </div>
            {enquiry.status === "new" || enquiry.status === "contacted" ? (
              <button className="button button-primary" type="button" disabled={pendingId === enquiry.id} onClick={() => approve(enquiry)}>
                {pendingId === enquiry.id ? "Generating…" : "Approve & generate link"}
              </button>
            ) : null}
            {invitationLinks[enquiry.id] && (
              <div className="invitation-output">
                <input readOnly value={invitationLinks[enquiry.id]} aria-label={`Invitation link for ${enquiry.full_name}`} />
                <button className="button button-secondary" type="button" onClick={() => copyLink(enquiry.id)}>Copy link</button>
              </div>
            )}
          </article>
        ))}
      </div>
    </div>
  );
}
