"use client";

import Link from "next/link";
import { useState, type FormEvent } from "react";
import { publicSupabaseEnvironment } from "@/lib/env/public";

export function EnquiryForm() {
  const [message, setMessage] = useState("");
  const [submitting, setSubmitting] = useState(false);

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const form = event.currentTarget;
    const values = new FormData(form);
    const name = String(values.get("name") ?? "").trim();
    const email = String(values.get("email") ?? "").trim().toLowerCase();
    const phone = String(values.get("phone") ?? "").replace(/[^+\d]/g, "");
    const termsAccepted = values.get("termsAccepted") === "yes";

    if (!name || !email || phone.length < 8 || !termsAccepted) {
      setMessage("Please complete the required fields and accept the terms.");
      return;
    }

    setSubmitting(true);
    setMessage("Submitting your enquiry…");

    try {
      const environment = publicSupabaseEnvironment();
      const response = await fetch(`${environment.url}/rest/v1/rpc/submit_enquiry`, {
        method: "POST",
        headers: { apikey: environment.anonKey, "Content-Type": "application/json" },
        body: JSON.stringify({ p_full_name: name, p_email: email, p_phone: phone, p_terms_accepted: true, p_marketing_consent: values.get("marketingConsent") === "yes" }),
      });
      const result = await response.json().catch(() => null);
      if (!response.ok) {
        if (String(result?.message ?? "").includes("recently submitted")) throw new Error("duplicate");
        throw new Error("failed");
      }
      setMessage(`Thank you. Enquiry ${String(result).slice(0, 8).toUpperCase()} has been received.`);
      form.reset();
    } catch (error) {
      setMessage(error instanceof Error && error.message === "duplicate" ? "An enquiry for this email was submitted recently. Our team will be in touch." : "We could not submit your enquiry. Please try again shortly.");
    } finally {
      setSubmitting(false);
    }
  }

  return <form className="contact-form" onSubmit={submit}><div className="form-heading"><span>Contact details</span><h3>Tell us how to reach you.</h3></div><label>Full Name<input name="name" autoComplete="name" required /></label><label>Email Address<input type="email" name="email" autoComplete="email" required /></label><label>Phone Number<input type="tel" name="phone" autoComplete="tel" required placeholder="+91" /></label><label className="consent-row"><input type="checkbox" name="termsAccepted" value="yes" required /><span>I agree to the <Link href="/terms">Terms</Link> and acknowledge the <Link href="/privacy">Privacy Notice</Link>.</span></label><label className="consent-row"><input type="checkbox" name="marketingConsent" value="yes" /><span>I would like occasional One Club updates. Optional.</span></label><button className="button button-primary" type="submit" disabled={submitting}>{submitting ? "Submitting…" : "Submit Enquiry"}</button><p className="form-message" aria-live="polite">{message}</p></form>;
}

