"use client";

import { createBrowserClient } from "@supabase/ssr";
import { publicSupabaseEnvironment } from "@/lib/env/public";
import type { Database } from "@/types/database";

export function createClient() {
  const environment = publicSupabaseEnvironment();
  return createBrowserClient<Database>(environment.url, environment.anonKey);
}

