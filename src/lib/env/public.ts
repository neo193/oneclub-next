export function publicSupabaseEnvironment() {
  // Next.js only exposes public environment variables to browser bundles when
  // they are referenced statically. Dynamic process.env indexing stays undefined.
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const anonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
  if (!url) throw new Error("NEXT_PUBLIC_SUPABASE_URL is required to connect to Supabase.");
  if (!anonKey) throw new Error("NEXT_PUBLIC_SUPABASE_ANON_KEY is required to connect to Supabase.");

  return {
    url,
    anonKey,
  };
}
