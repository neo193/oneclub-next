"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { useEffect, useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { useToast } from "@/components/ui/toast-provider";
import type { MemberSupportRequest, Profile } from "@/types/database";

const friendly = (value: string) => value.replaceAll("_", " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
const statusLabel: Record<MemberSupportRequest["status"], string> = {
  open: "Received",
  in_progress: "In progress",
  resolved: "Resolved",
};

export function MemberSupportForm({
  profile,
  userEmail,
  initialTickets,
  ticketsError,
}: {
  profile: Profile;
  userEmail: string;
  initialTickets: MemberSupportRequest[];
  ticketsError: string;
}) {
  const router = useRouter();
  const searchParams = useSearchParams();
  const deletionContext = searchParams.get("accountDeletion");
  const initialCategory = "membership_access";
  const initialReservation = searchParams.get("reservation");

  const [category, setCategory] = useState<string>(initialCategory);
  const [message, setMessage] = useState<string>(
    initialReservation ? `Regarding reservation reference: ${initialReservation}\n\n` : ""
  );
  const [statusText, setStatusText] = useState<string>("");
  const [pending, setPending] = useState<boolean>(false);
  const [deletionEscalation, setDeletionEscalation] = useState(false);
  const { notify } = useToast();
  const duplicateTicket = initialTickets.find((ticket) => ticket.category === category && ticket.status !== "resolved");

  useEffect(()=>{if(!deletionContext)return;void (async()=>{const {data}=await createClient().rpc("validate_account_deletion_support_context",{p_context:deletionContext});if(data){setDeletionEscalation(true);setCategory("account_deletion");setMessage("Please expedite the unresolved refund(s) so I can delete my account.\n\n");}})();},[deletionContext]);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!message.trim()) return;

    setPending(true);
    setStatusText("Sending your support request…");

    try {
      const supabase = createClient();
      const { data, error } = deletionEscalation&&deletionContext
        ? await supabase.rpc("submit_account_deletion_support_request",{p_context:deletionContext,p_message:message.trim()})
        : await supabase.rpc("submit_member_support_request", {p_category: category,p_message: message.trim()});

      if (error) throw new Error(error.message);

      setStatusText(`Support request submitted. Reference: ${data || "Logged"}. Our team will respond shortly.`);
      notify("Support request submitted successfully.", "success");
      setMessage("");
      router.refresh();
    } catch (err) {
      const errorMessage = err instanceof Error ? err.message : "Could not submit your request. Please try again.";
      setStatusText(errorMessage);
      notify(errorMessage, "error");
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

        <section className="member-ticket-panel">
          <div className="member-ticket-heading">
            <div>
              <small>Support progress</small>
              <h3>Active tickets</h3>
            </div>
            <span>{initialTickets.length}</span>
          </div>
          {ticketsError ? <p className="member-ticket-empty">Ticket progress is temporarily unavailable.</p> : initialTickets.length ? (
            <div className="member-ticket-list">
              {initialTickets.map((ticket) => (
                <article className={`member-ticket member-ticket-${ticket.status}`} key={ticket.id}>
                  <div>
                    <strong>{friendly(ticket.category)}</strong>
                    <small>Updated {new Date(ticket.updated_at).toLocaleDateString()}</small>
                  </div>
                  <span>{statusLabel[ticket.status]}</span>
                </article>
              ))}
            </div>
          ) : <p className="member-ticket-empty">You have no active support tickets.</p>}
        </section>
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
            disabled={deletionEscalation}
            required
          >
            {deletionEscalation&&<option value="account_deletion">Account deletion</option>}
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

        {duplicateTicket && <p className="support-duplicate-note">You already have a {statusLabel[duplicateTicket.status].toLowerCase()} ticket for this category. You can send another after it is resolved.</p>}
        <button className="button button-primary" type="submit" disabled={pending || Boolean(duplicateTicket)}>
          {pending ? "Submitting…" : "Send Request"}
        </button>

        <p className="form-message" aria-live="polite">
          {statusText}
        </p>
      </form>
    </div>
  );
}

