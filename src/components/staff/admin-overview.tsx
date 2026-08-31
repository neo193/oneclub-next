"use client";

import { useState } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Json } from "@/types/database";

type MetricGroup = Record<string, string | number | boolean | null>;
type OverviewData = {
  checked_at?: string;
  audit_entries?: number;
  profiles?: MetricGroup;
  sales?: MetricGroup;
  support?: MetricGroup;
  events?: MetricGroup;
  payments?: MetricGroup;
  content?: MetricGroup;
};

const groups: [keyof OverviewData, string][] = [
  ["profiles", "Accounts & membership"], ["sales", "Sales pipeline"], ["support", "Support queue"],
  ["events", "Events & bookings"], ["payments", "Payment attempts"], ["content", "Member content"],
];
const attention = new Set(["suspended_members", "payment_pending_members", "new_enquiries", "open", "in_progress", "pending_bookings", "created", "failed"]);
const friendly = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());

function asOverview(value: Json | null): OverviewData {
  return value && typeof value === "object" && !Array.isArray(value) ? value as OverviewData : {};
}

export function AdminOverview({ initialData, initialError }: { initialData: Json | null; initialError: string }) {
  const [data, setData] = useState(() => asOverview(initialData));
  const [message, setMessage] = useState(initialError || "Business overview current.");
  const [pending, setPending] = useState(false);

  async function refresh() {
    setPending(true); setMessage("Refreshing business overview…");
    try {
      const supabase = createClient();
      const { data: result, error } = await supabase.rpc("get_technical_diagnostics");
      if (error) throw new Error(error.message);
      setData(asOverview(result)); setMessage("Business overview refreshed.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Overview refresh failed.");
    } finally { setPending(false); }
  }

  return (
    <div className="staff-workspace">
      <div className="staff-toolbar overview-toolbar">
        <div><strong>Overview current</strong><p>{data.checked_at ? `Last checked ${new Date(data.checked_at).toLocaleString("en-IN")}` : "No check time available"}</p></div>
        <button className="button button-secondary" type="button" disabled={pending} onClick={refresh}>{pending ? "Refreshing…" : "Refresh"}</button>
      </div>
      <p className="form-message" aria-live="polite">{message}</p>
      <div className="overview-grid-next">
        {groups.map(([key, title], index) => {
          const metrics = data[key] as MetricGroup | undefined;
          return (
            <article className="overview-card-next" key={String(key)}>
              <header><span>{String(index + 1).padStart(2, "0")}</span><h2>{title}</h2></header>
              <div className="overview-metrics-next">
                {Object.entries(metrics || {}).map(([name, value]) => {
                  const numeric = typeof value === "number" ? value : Number(value);
                  const needsAttention = attention.has(name) && Number.isFinite(numeric) && numeric > 0;
                  return <div className={needsAttention ? "needs-attention" : numeric === 0 ? "is-zero" : ""} key={name}><strong>{String(value ?? "—")}</strong><span>{friendly(name)}</span></div>;
                })}
              </div>
            </article>
          );
        })}
        <article className="overview-card-next overview-audit-next"><header><span>07</span><h2>Audit trail</h2></header><div className="overview-metrics-next"><div><strong>{data.audit_entries ?? 0}</strong><span>Recorded entries</span></div></div></article>
      </div>
    </div>
  );
}
