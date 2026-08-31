"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

export function ResetPasswordForm() {
  const router=useRouter(); const [message,setMessage]=useState(""); const [pending,setPending]=useState(false);
  async function submit(event:FormEvent<HTMLFormElement>){
    event.preventDefault(); const values=new FormData(event.currentTarget); const password=String(values.get("password")??""); const confirmation=String(values.get("confirm_password")??"");
    if(password!==confirmation){setMessage("The passwords do not match.");return;}
    setPending(true);setMessage("Updating password…"); const supabase=createClient();
    const {data:claims}=await supabase.auth.getClaims(); if(!claims?.claims){setMessage("This recovery link is invalid or has expired. Request a new one.");setPending(false);return;}
    const {error}=await supabase.auth.updateUser({password}); if(error){setMessage(error.message);setPending(false);return;}
    await supabase.auth.signOut(); setMessage("Password updated. Redirecting to sign in…"); router.replace("/login?password=updated"); router.refresh();
  }
  return <form className="contact-form auth-form" onSubmit={submit}><div className="form-heading"><span>New credentials</span><h3>Update your password.</h3></div><label>New password<input type="password" name="password" autoComplete="new-password" required minLength={8}/></label><label>Confirm new password<input type="password" name="confirm_password" autoComplete="new-password" required minLength={8}/></label><button className="button button-primary" type="submit" disabled={pending}>{pending?"Updating…":"Update password"}</button><p className="form-message" aria-live="polite">{message}</p></form>;
}
