"use client";

import { useEffect, useState } from "react";
import type { TechnicalDiagnostics } from "@/types/diagnostics";

type Card = { title: string; status: string; description: string; detail?: string | null; metrics: Record<string, string | number | null> };
const friendly = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
const state = (value: string) => /operational|connected|success|deployed/i.test(value) ? "healthy" : /not configured/i.test(value) ? "neutral" : "unhealthy";

function cards(data: TechnicalDiagnostics): Card[] {
  return [
    { title: "Application", status: data.application.status, metrics: { response_time: `${data.application.latency_ms} ms` }, description: "Checks that the website is reachable through the current deployment." },
    { title: "Supabase", status: data.supabase.database_status, metrics: { database_response: `${data.supabase.database_latency_ms} ms`, authentication: data.supabase.auth_status, auth_response: `${data.supabase.auth_latency_ms} ms` }, description: "Checks authenticated database access and the authentication service." },
    { title: "Payments", status: data.payments.service_status, metrics: { failed: data.payments.failed, unreconciled: data.payments.unreconciled }, description: "Surfaces payment records that may need technical reconciliation." },
    { title: "Cloudflare deployment", status: data.deployment.status, metrics: { deployment_reference: data.deployment.reference || "—", deployed: data.deployment.deployed_at ? new Date(data.deployment.deployed_at).toLocaleString("en-IN") : "—" }, description: "Reports the Worker deployment currently serving production traffic when provider access is configured." },
    { title: "Security", status: data.security.status, metrics: { blocked_24h: data.security.blocked_24h, challenged_24h: data.security.challenged_24h }, description: "Summarizes Cloudflare security actions without exposing visitor identities.", detail: data.security.detail },
    { title: "Data integrity", status: "Connected", metrics: { pending_event_holds: data.data_integrity.pending_event_holds, pending_refunds: data.data_integrity.pending_refunds, suspended_members: data.data_integrity.suspended_members }, description: "Highlights operational records that may require investigation or follow-up." },
  ];
}

export function TechnicalDiagnosticsWorkspace() {
  const [data, setData] = useState<TechnicalDiagnostics | null>(null);
  const [message, setMessage] = useState("Running live service checks…");
  const [pending, setPending] = useState(true);

  async function load() {
    setPending(true); setMessage("Running live service checks…");
    try {
      const response = await fetch("/api/technical-diagnostics", { cache: "no-store" });
      const result = await response.json().catch(() => null);
      if (!response.ok) throw new Error(result?.message || "Technical checks failed.");
      setData(result);
      setMessage(result.provider_configuration.cloudflare_api && result.provider_configuration.cloudflare_security ? "All configured checks completed." : "Core checks completed. Cloudflare provider metrics require configuration.");
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "Technical checks failed.");
    } finally { setPending(false); }
  }

  useEffect(() => {
    let active = true;

    fetch("/api/technical-diagnostics", { cache: "no-store" })
      .then(async (response) => {
        const result = await response.json().catch(() => null);
        if (!response.ok) throw new Error(result?.message || "Technical checks failed.");
        return result as TechnicalDiagnostics;
      })
      .then((result) => {
        if (!active) return;
        setData(result);
        setMessage(result.provider_configuration.cloudflare_api && result.provider_configuration.cloudflare_security ? "All configured checks completed." : "Core checks completed. Cloudflare provider metrics require configuration.");
      })
      .catch((error: unknown) => {
        if (active) setMessage(error instanceof Error ? error.message : "Technical checks failed.");
      })
      .finally(() => {
        if (active) setPending(false);
      });

    return () => { active = false; };
  }, []);
  const diagnosticsCards = data ? cards(data) : [];
  const unhealthy = diagnosticsCards.some((card) => state(card.status) === "unhealthy");

  return (
    <div className="staff-workspace">
      <div className="staff-toolbar diagnostics-toolbar-next">
        <div><strong className={unhealthy ? "unhealthy" : data ? "healthy" : "neutral"}>{unhealthy ? "Attention required" : data ? "Core systems operational" : "Checking"}</strong><p>{data ? `Last checked ${new Date(data.checked_at).toLocaleString("en-IN")}` : "—"}</p></div>
        <button className="button button-secondary" type="button" disabled={pending} onClick={load}>{pending ? "Running…" : "Run checks"}</button>
      </div>
      <p className="form-message" aria-live="polite">{message}</p>
      <div className="technical-grid-next">
        {diagnosticsCards.map((card, index) => (
          <article className="technical-card-next" key={card.title}>
            <header><span>{String(index + 1).padStart(2, "0")}</span><h2>{card.title}</h2><strong className={state(card.status)}>{card.status}</strong></header>
            <p>{card.description}</p>
            {card.detail ? <p className="form-message">Cloudflare response: {card.detail}</p> : null}
            <div>{Object.entries(card.metrics).map(([name, value]) => <span key={name}><strong>{value ?? "—"}</strong><small>{friendly(name)}</small></span>)}</div>
          </article>
        ))}
      </div>
      <p className="staff-security-note">Provider tokens remain on the server. This page never receives secrets, raw security logs, member records or IP addresses.</p>
    </div>
  );
}

