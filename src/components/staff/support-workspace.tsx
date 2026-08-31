"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { StaffSupportRequest } from "@/types/database";

type SupportStatus = StaffSupportRequest["status"];
const statuses: SupportStatus[] = ["open", "in_progress", "resolved", "closed"];
const friendly = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());

export function SupportWorkspace({ initialRequests, initialError }: { initialRequests: StaffSupportRequest[]; initialError: string }) {
  const [requests, setRequests] = useState(initialRequests);
  const [filter, setFilter] = useState("");
  const [message, setMessage] = useState(initialError || `${initialRequests.length} support requests loaded.`);
  const [pendingId, setPendingId] = useState<string | null>(null);

  async function load(nextFilter = filter) {
    setMessage("Loading support requests…");
    const supabase = createClient();
    const { data, error } = await supabase.rpc("list_support_requests_for_staff", { p_status: nextFilter || null });
    if (error) throw new Error(error.message);
    setRequests(data || []);
    setMessage(`${data?.length || 0} support ${data?.length === 1 ? "request" : "requests"} loaded.`);
  }

  async function updateStatus(request: StaffSupportRequest, status: SupportStatus) {
    setPendingId(request.id);
    setMessage(`Updating ${request.full_name || request.email}…`);
    try {
      const supabase = createClient();
      const { error } = await supabase.rpc("update_support_request_status", { p_request_id: request.id, p_status: status });
      if (error) throw new Error(error.message);
      setRequests((rows) => rows.map((row) => row.id === request.id ? { ...row, status } : row));
      setMessage(`Request updated to ${friendly(status)}.`);
      if (filter && filter !== status) setRequests((rows) => rows.filter((row) => row.id !== request.id));
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Support request could not be updated.");
    } finally {
      setPendingId(null);
    }
  }

  return (
    <div className="staff-workspace">
      <div className="staff-toolbar support-toolbar-next">
        <label>Status filter
          <select value={filter} onChange={(event) => { const value = event.target.value; setFilter(value); void load(value).catch((error) => setMessage(error.message)); }}>
            <option value="">All requests</option>
            {statuses.map((status) => <option value={status} key={status}>{friendly(status)}</option>)}
          </select>
        </label>
        <p className="form-message" aria-live="polite">{message}</p>
      </div>
      <div className="support-request-list-next">
        {requests.length === 0 ? <p className="staff-empty">No support requests match this filter.</p> : requests.map((request) => (
          <article className={`support-request-card-next support-state-${request.status}`} key={request.id}>
            <header>
              <div>
                <p className="eyebrow compact">{friendly(request.category)}</p>
                <h2>{request.full_name || request.email}</h2>
                <small>{request.email} · {request.member_number || "No member ID"} · {friendly(request.membership_state)}</small>
              </div>
              <span className="support-status-next"><i aria-hidden="true" />{friendly(request.status)}</span>
            </header>
            <p className="support-message-next">{request.message}</p>
            <div className="support-controls-next">
              <label>Status
                <select value={request.status} disabled={pendingId === request.id} onChange={(event) => updateStatus(request, event.target.value as SupportStatus)}>
                  {statuses.map((status) => <option value={status} key={status}>{friendly(status)}</option>)}
                </select>
              </label>
              <span>{pendingId === request.id ? "Saving update…" : "Changes save immediately"}</span>
            </div>
          </article>
        ))}
      </div>
    </div>
  );
}
