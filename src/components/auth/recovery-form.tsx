"use client";

import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

export function RecoveryForm({ initialMessage = "" }: { initialMessage?: string }) {
  const [message, setMessage] = useState(initialMessage); const [pending, setPending] = useState(false);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); const form=event.currentTarget; const email=String(new FormData(form).get("email")??"").trim().toLowerCase();
    setPending(true); setMessage("Requesting a secure recovery link…");
    const redirectTo=`${location.origin}/auth/callback?next=${encodeURIComponent("/reset-password")}`;
    const { error }=await createClient().auth.resetPasswordForEmail(email,{redirectTo});
    if(error){setMessage(error.message);setPending(false);return;}
    setMessage("If an account is registered with that email address, password recovery instructions will arrive shortly."); form.reset(); setPending(false);
  }
  return <form className="contact-form auth-form" onSubmit={submit}><div className="form-heading"><span>Secure recovery</span><h3>Request a reset link.</h3></div><label>Email Address<input type="email" name="email" autoComplete="email" required /></label><button className="button button-primary" type="submit" disabled={pending}>{pending?"Requesting…":"Send recovery email"}</button><p className="form-message" aria-live="polite">{message}</p></form>;
}
