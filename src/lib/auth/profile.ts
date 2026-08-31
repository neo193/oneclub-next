import "server-only";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Profile } from "@/types/database";

export async function getAuthenticatedProfile(): Promise<Profile | null> {
  const supabase = await createClient();
  const { data: claimsData, error: claimsError } = await supabase.auth.getClaims();
  const subject = claimsData?.claims?.sub;

  if (claimsError || !subject) return null;

  const { data, error } = await supabase.from("profiles").select("id,full_name,app_role,staff_role,membership_state,member_number,founding_member_sequence,payment_offer_expires_at").eq("id", subject).single();
  if (error || !data) return null;
  return data;
}

export async function requireProfile(nextPath: string) {
  const profile = await getAuthenticatedProfile();
  if (!profile) redirect(`/login?next=${encodeURIComponent(nextPath)}`);
  return profile;
}

export function destinationForProfile(profile: Pick<Profile, "app_role">) {
  return profile.app_role === "member" ? "/portal" : "/staff";
}
