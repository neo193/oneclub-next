"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";

type Invitation = { email: string; expires_at: string; status: string };

export function InvitationCard({ token }: { token: string | null }) {
  const router=useRouter(); const [invitation,setInvitation]=useState<Invitation|null>(null); const [signedIn,setSignedIn]=useState(false); const [loading,setLoading]=useState(true); const [message,setMessage]=useState(""); const [pending,setPending]=useState(false);

  useEffect(()=>{
    let active=true;
    async function load(){
      if(!token){setMessage("This invitation link is incomplete.");setLoading(false);return;}
      const supabase=createClient(); const [{data,error},{data:userData}]=await Promise.all([supabase.rpc("validate_membership_invitation",{p_token:token}),supabase.auth.getUser()]);
      if(!active)return; const info=data?.[0];
      if(error){setMessage(error.message);setLoading(false);return;}
      if(!info||info.status!=="active"){setMessage("This invitation is invalid, expired or already used.");setLoading(false);return;}
      setInvitation(info);setSignedIn(Boolean(userData.user));setLoading(false);
    }
    void load(); return()=>{active=false;};
  },[token]);

  async function createAccount(event:FormEvent<HTMLFormElement>){
    event.preventDefault(); if(!invitation||!token)return; const values=new FormData(event.currentTarget); const password=String(values.get("password")??"");
    if(password!==String(values.get("confirm_password")??"")){setMessage("The passwords do not match.");return;}
    setPending(true);setMessage("Creating your secure account…"); const supabase=createClient(); const next=`/membership-invite?token=${encodeURIComponent(token)}`;
    const {data,error}=await supabase.auth.signUp({email:invitation.email,password,options:{data:{full_name:String(values.get("full_name")??"").trim()},emailRedirectTo:`${location.origin}/auth/callback?next=${encodeURIComponent(next)}`}});
    if(error){setMessage(error.message);setPending(false);return;}
    if(data.session){setSignedIn(true);setMessage("Account created. Accept the invitation to continue.");setPending(false);return;}
    setMessage("Account created. Check your email to confirm the account, then return to this invitation.");
  }

  async function accept(){
    if(!token)return;setPending(true);setMessage("Connecting this invitation to your account…"); const {error}=await createClient().rpc("accept_membership_invitation",{p_token:token});
    if(error){setMessage(error.message);setPending(false);return;}
    setMessage("Invitation accepted. Taking you to your portal…");router.replace("/portal");router.refresh();
  }

  if(loading)return <section className="contact-form invite-card"><p>Validating invitation…</p></section>;
  if(!invitation)return <section className="contact-form invite-card"><div className="form-heading"><span>Invitation unavailable</span><h3>We could not validate this link.</h3></div><p className="form-message">{message}</p><Link className="button button-secondary" href="/contact">Contact One Club</Link></section>;

  return <section className="contact-form invite-card"><div className="form-heading"><span>Approved access</span><h3>One Club Founding Member</h3></div><div className="invite-fact"><small>Approved email</small><strong>{invitation.email}</strong></div><div className="invite-fact"><small>Invitation expiry</small><strong>{new Date(invitation.expires_at).toLocaleString()}</strong></div><div className="membership-meta"><span><small>Price</small>₹50,000</span><span><small>Validity</small>Lifetime</span></div>{signedIn?<button className="button button-primary" type="button" onClick={accept} disabled={pending}>{pending?"Accepting…":"Accept invitation"}</button>:<><div className="form-heading invite-account-heading"><span>Private account</span><h3>Create your account.</h3></div><form className="invite-signup" onSubmit={createAccount}><label>Full name<input name="full_name" autoComplete="name" required maxLength={100}/></label><label>Approved email<input type="email" value={invitation.email} readOnly/></label><label>Create password<input type="password" name="password" autoComplete="new-password" required minLength={8}/></label><label>Confirm password<input type="password" name="confirm_password" autoComplete="new-password" required minLength={8}/></label><button className="button button-primary" type="submit" disabled={pending}>{pending?"Creating…":"Create account"}</button><Link className="button button-secondary" href={`/login?next=${encodeURIComponent(`/membership-invite?token=${token}`)}`}>I already have an account</Link></form></>}<p className="form-message" aria-live="polite">{message}</p></section>;
}
