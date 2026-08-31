"use client";

import { useSearchParams } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Profile } from "@/types/database";

export function MemberSupportForm({
  profile,
  userEmail,
}: {
  profile: Profile;
  userEmail: string;
}) {
  const searchParams = useSearchParams();
  const initialCategory = searchParams.get("category") || "membership_access";
  const initialReservation = searchParams.get("reservation");

  const [category, setCategory] = useState<string>(initialCategory);
  const [message, setMessage] = useState<string>(
    initialReservation ? `Regarding reservation reference: ${initialReservation}\n\n` : ""
  );
  const [statusText, setStatusText] = useState<string>("");
  const [pending, setPending] = useState<boolean>(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!message.trim()) return;

    setPending(true);
    setStatusText("Sending your support request…");

    try {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("submit_member_support_request", {
        p_category: category,
        p_message: message.trim(),
      });

      if (error) throw new Error(error.message);

      setStatusText(`Support request submitted. Reference: ${data || "Logged"}. Our team will respond shortly.`);
      setMessage("");
    } catch (err) {
      setStatusText(err instanceof Error ? err.message : "Could not submit your request. Please try again.");
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="auth-layout" style={{ width: "100%", padding: 0 }}>
      {/* Identity Info Panel */}
      <section className="auth-intro">
        <p className="eyebrow compact">
          <span />
          PRIVATE CONCIERGE
        </p>
        <h2>
          How can<br />
          <em>we assist you?</em>
        </h2>
        <p>
          This private channel connects directly to the One Club membership desk for personalized assistance with reservations, events, payments, or privileges.
        </p>

        <div className="support-identity">
          <small>Signed in as</small>
          <strong>{userEmail}</strong>
          <span>
            {profile.member_number || "Pending Member ID"} · {profile.membership_state.replace("_", " ")}
          </span>
        </div>
      </section>

      {/* Support Form */}
      <form className="contact-form auth-form" onSubmit={handleSubmit}>
        <div className="form-heading">
          <span>Direct message</span>
          <h3>Contact the desk.</h3>
        </div>

        <label>
          Topic / Category
          <select
            value={category}
            onChange={(e) => setCategory(e.target.value)}
            required
          >
            <option value="membership_access">Membership access</option>
            <option value="payment">Payment & Billing</option>
            <option value="event_booking">Event booking & Guest places</option>
            <option value="reservation_change">Partner property reservation</option>
            <option value="profile">Profile & Information</option>
            <option value="other">Other inquiry</option>
          </select>
        </label>

        <label>
          Your Message
          <textarea
            required
            minLength={10}
            maxLength={2000}
            rows={5}
            placeholder="Tell us what happened and how we can assist you."
            value={message}
            onChange={(e) => setMessage(e.target.value)}
          />
        </label>

        <button className="button button-primary" type="submit" disabled={pending}>
          {pending ? "Submitting…" : "Send Request"}
        </button>

        <p className="form-message" aria-live="polite">
          {statusText}
        </p>
      </form>
    </div>
  );
}

