import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { publicSupabaseEnvironment } from "@/lib/env/public";
import type { Database } from "@/types/database";

export async function createClient() {
  const cookieStore = await cookies();
  const environment = publicSupabaseEnvironment();

  return createServerClient<Database>(environment.url, environment.anonKey, {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) =>
            cookieStore.set(name, value, options),
          );
        } catch {
          // Server Components cannot write cookies. Proxy/session refresh will do so.
        }
      },
    },
  });
}

