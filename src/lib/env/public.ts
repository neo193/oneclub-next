function requiredPublicValue(name: "NEXT_PUBLIC_SUPABASE_URL" | "NEXT_PUBLIC_SUPABASE_ANON_KEY") {
  const value = process.env[name];

  if (!value) {
    throw new Error(`${name} is required to connect to Supabase.`);
  }

  return value;
}

export function publicSupabaseEnvironment() {
  return {
    url: requiredPublicValue("NEXT_PUBLIC_SUPABASE_URL"),
    anonKey: requiredPublicValue("NEXT_PUBLIC_SUPABASE_ANON_KEY"),
  };
}

