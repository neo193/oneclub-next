"use server";

import { redirect } from "next/navigation";
import { safeInternalPath } from "@/lib/auth/redirects";
import { createClient } from "@/lib/supabase/server";

export type LoginState = { message: string };

export async function loginAction(nextPath: string, _state: LoginState, formData: FormData): Promise<LoginState> {
  const email = String(formData.get("email") || "").trim().toLowerCase();
  const password = String(formData.get("password") || "");
  if (!email || !password) return { message: "Enter your email address and password." };

  const supabase = await createClient();
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error || !data.user) {
    return {
      message: error?.message === "Invalid login credentials"
        ? "Email or password is incorrect."
        : error?.message || "Sign in could not be completed.",
    };
  }

  let destination = safeInternalPath(nextPath, "/portal");
  if (destination === "/portal") {
    const { data: profile } = await supabase
      .from("profiles")
      .select("app_role")
      .eq("id", data.user.id)
      .single();
    if (profile && (profile.app_role === "staff" || profile.app_role === "admin")) destination = "/staff";
  }
  redirect(destination);
}
