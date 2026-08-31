export type TechnicalDiagnostics = {
  checked_at: string;
  application: { status: string; latency_ms: number };
  supabase: { database_status: string; database_latency_ms: number; auth_status: string; auth_latency_ms: number };
  payments: { service_status: string; failed: number; unreconciled: number };
  deployment: { configured: boolean; status: string; deployed_at?: string | null; commit?: string | null };
  security: { configured: boolean; status: string; blocked_24h: number | null; challenged_24h: number | null };
  data_integrity: { pending_event_holds: number; pending_refunds: number | null; suspended_members: number };
  provider_configuration: { cloudflare_api: boolean; cloudflare_security: boolean };
};
