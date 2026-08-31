"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

export function LoginForm({ nextPath, initialMessage = "" }: { nextPath: string; initialMessage?: string }) {
  const router = useRouter();
  const [message, setMessage] = useState(initialMessage);
  const [pending, setPending] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const values = new FormData(event.currentTarget);
    setPending(true); setMessage("Signing in…");
    const supabase = createClient();
    const { data, error } = await supabase.auth.signInWithPassword({ email: String(values.get("email") ?? "").trim().toLowerCase(), password: String(values.get("password") ?? "") });
    if (error) { setMessage(error.message === "Invalid login credentials" ? "Email or password is incorrect." : error.message); setPending(false); return; }
    let destination = nextPath;
    if (nextPath === "/portal" && data.user) {
      const { data: profile } = await supabase.from("profiles").select("app_role").eq("id", data.user.id).single();
      if (profile && ["staff", "admin"].includes(profile.app_role)) destination = "/staff";
    }
    // Do not immediately refresh here: it can race router.replace and reload
    // the login page before the protected navigation completes.
    router.replace(destination);
  }

  return <form className="contact-form auth-form" onSubmit={submit}><div className="form-heading"><span>Secure login</span><h3>Access your account.</h3></div><label>Email Address<input type="email" name="email" autoComplete="email" required /></label><label>Password<input type="password" name="password" autoComplete="current-password" required minLength={8} /></label><p className="auth-helper"><Link href="/forgot-password">Forgot password?</Link></p><button className="button button-primary" type="submit" disabled={pending}>{pending ? "Signing in…" : "Sign in"}</button><p className="form-message" aria-live="polite">{message}</p><p className="privacy-note">New member accounts can only be created from a valid invitation link.</p></form>;
}
