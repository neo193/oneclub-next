"use client";

import Link from "next/link";
import { useActionState, type FocusEvent } from "react";
import { loginAction, type LoginState } from "@/app/(auth)/login/actions";

export function LoginForm({ nextPath, initialMessage = "" }: { nextPath: string; initialMessage?: string }) {
  const initialState: LoginState = { message: initialMessage };
  const [state, formAction, pending] = useActionState(loginAction.bind(null, nextPath), initialState);

  function enableCredentialEntry(event: FocusEvent<HTMLInputElement>) {
    event.currentTarget.readOnly = false;
  }

  return <form className="contact-form auth-form" action={formAction}><div className="form-heading"><span>Secure login</span><h3>Access your account.</h3></div><label>Email Address<input type="email" name="email" autoComplete="email" placeholder="" readOnly onFocus={enableCredentialEntry} required /></label><label>Password<input type="password" name="password" autoComplete="current-password" placeholder="" readOnly onFocus={enableCredentialEntry} required minLength={8} /></label><p className="auth-helper"><Link href="/forgot-password">Forgot password?</Link></p><button className="button button-primary" type="submit" disabled={pending}>{pending ? "Signing in…" : "Sign in"}</button><p className="form-message" aria-live="polite">{state.message}</p><p className="privacy-note">New member accounts can only be created from a valid invitation link.</p></form>;
}
