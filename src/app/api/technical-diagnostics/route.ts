import { NextResponse, type NextRequest } from "next/server";
import { getAuthenticatedProfile } from "@/lib/auth/profile";
import { publicSupabaseEnvironment } from "@/lib/env/public";
import { createClient } from "@/lib/supabase/server";
import type { TechnicalDiagnostics } from "@/types/diagnostics";

type TimedResult<T> = { ok: true; latency: number; value: T } | { ok: false; latency: number; error: string };
async function timed<T>(task: () => Promise<T>): Promise<TimedResult<T>> {
  const started = Date.now();
  try { return { ok: true, latency: Date.now() - started, value: await task() }; }
  catch (error) { return { ok: false, latency: Date.now() - started, error: error instanceof Error ? error.message : "Check failed" }; }
}
async function fetchJson(url: string, init?: RequestInit) {
  const response = await fetch(url, { ...init, cache: "no-store" });
  const data = await response.json().catch(() => null);
  if (!response.ok) throw new Error(data?.errors?.[0]?.message || data?.message || `HTTP ${response.status}`);
  return data;
}

export async function GET(request: NextRequest) {
  const profile = await getAuthenticatedProfile();
  if (!profile) return NextResponse.json({ message: "Authentication required" }, { status: 401 });
  if (!(profile.app_role === "admin" || (profile.app_role === "staff" && profile.staff_role === "technical"))) {
    return NextResponse.json({ message: "Technical diagnostics permission required" }, { status: 403 });
  }

  const environment = publicSupabaseEnvironment();
  const supabase = await createClient();
  const origin = new URL(request.url).origin;
  const [application, auth, database, pendingRefunds] = await Promise.all([
    timed(async () => { const response = await fetch(`${origin}/`, { cache: "no-store" }); if (!response.ok) throw new Error(`HTTP ${response.status}`); return response.status; }),
    timed(async () => { const response = await fetch(`${environment.url}/auth/v1/health`, { headers: { apikey: environment.anonKey }, cache: "no-store" }); if (!response.ok) throw new Error(`HTTP ${response.status}`); return response.status; }),
    timed(async () => { const { data, error } = await supabase.rpc("get_technical_diagnostics"); if (error) throw new Error(error.message); return data; }),
    timed(async () => { const { data, error } = await supabase.rpc("get_pending_refund_count"); if (error) throw new Error(error.message); return Number(data || 0); }),
  ]);

  let deployment: TechnicalDiagnostics["deployment"] = { configured: false, status: "Not configured" };
  if (process.env.CLOUDFLARE_API_TOKEN && process.env.CLOUDFLARE_ACCOUNT_ID && process.env.CLOUDFLARE_PAGES_PROJECT) {
    const result = await timed(async () => {
      const data = await fetchJson(`https://api.cloudflare.com/client/v4/accounts/${process.env.CLOUDFLARE_ACCOUNT_ID}/pages/projects/${process.env.CLOUDFLARE_PAGES_PROJECT}/deployments?env=production&per_page=1`, { headers: { Authorization: `Bearer ${process.env.CLOUDFLARE_API_TOKEN}` } });
      const latest = data.result?.[0];
      return { status: latest?.latest_stage?.status || "Unknown", deployed_at: latest?.modified_on || null, commit: latest?.deployment_trigger?.metadata?.commit_hash?.slice(0, 8) || latest?.short_id || "—" };
    });
    deployment = result.ok ? { configured: true, ...result.value } : { configured: true, status: "Check failed" };
  }

  let security: TechnicalDiagnostics["security"] = { configured: false, status: "Not configured", blocked_24h: null, challenged_24h: null };
  if (process.env.CLOUDFLARE_API_TOKEN && process.env.CLOUDFLARE_ZONE_ID) {
    const until = new Date(); const since = new Date(until.getTime() - 86_400_000);
    const query = "query($zoneTag:String!,$filter:FirewallEventsAdaptiveGroupsFilter_InputObject){viewer{zones(filter:{zoneTag:$zoneTag}){firewallEventsAdaptiveGroups(limit:100,filter:$filter){count dimensions{action}}}}}";
    const result = await timed(async () => {
      const data = await fetchJson("https://api.cloudflare.com/client/v4/graphql", { method: "POST", headers: { Authorization: `Bearer ${process.env.CLOUDFLARE_API_TOKEN}`, "Content-Type": "application/json" }, body: JSON.stringify({ query, variables: { zoneTag: process.env.CLOUDFLARE_ZONE_ID, filter: { datetime_geq: since.toISOString(), datetime_leq: until.toISOString() } } }) });
      const rows = data.data?.viewer?.zones?.[0]?.firewallEventsAdaptiveGroups || [];
      return {
        blocked_24h: rows.filter((row: { dimensions?: { action?: string } }) => ["block", "drop"].includes(String(row.dimensions?.action))).reduce((sum: number, row: { count?: number }) => sum + Number(row.count || 0), 0),
        challenged_24h: rows.filter((row: { dimensions?: { action?: string } }) => String(row.dimensions?.action).includes("challenge")).reduce((sum: number, row: { count?: number }) => sum + Number(row.count || 0), 0),
      };
    });
    security = result.ok ? { configured: true, status: "Connected", ...result.value } : { configured: true, status: "Check failed", blocked_24h: null, challenged_24h: null };
  }

  const operational = database.ok && database.value && typeof database.value === "object" && !Array.isArray(database.value) ? database.value as Record<string, Record<string, number>> : {};
  const response: TechnicalDiagnostics = {
    checked_at: new Date().toISOString(),
    application: { status: application.ok ? "Operational" : "Unavailable", latency_ms: application.latency },
    supabase: { database_status: database.ok ? "Connected" : "Unavailable", database_latency_ms: database.latency, auth_status: auth.ok ? "Connected" : "Unavailable", auth_latency_ms: auth.latency },
    payments: { service_status: database.ok ? "Connected" : "Unavailable", failed: operational.payments?.failed || 0, unreconciled: (operational.payments?.created || 0) + (operational.events?.pending_bookings || 0) },
    deployment, security,
    data_integrity: { pending_event_holds: operational.events?.pending_bookings || 0, pending_refunds: pendingRefunds.ok ? pendingRefunds.value : null, suspended_members: operational.profiles?.suspended_members || 0 },
    provider_configuration: { cloudflare_api: deployment.configured, cloudflare_security: security.configured },
  };
  return NextResponse.json(response, { headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" } });
}
