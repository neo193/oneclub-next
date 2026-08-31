"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import type { MemberEvent, MyEventBooking } from "@/types/database";

function formatRupees(paise: number) {
  return new Intl.NumberFormat("en-IN", {
    style: "currency",
    currency: "INR",
    maximumFractionDigits: 0,
  }).format(paise / 100);
}

function formatDate(iso: string) {
  try {
    return new Intl.DateTimeFormat("en-IN", {
      dateStyle: "medium",
      timeStyle: "short",
      timeZone: "Asia/Kolkata",
    }).format(new Date(iso));
  } catch {
    return iso;
  }
}

export function EventBookingView({
  initialEvents = [],
  initialBookings = [],
}: {
  initialEvents: MemberEvent[];
  initialBookings: MyEventBooking[];
}) {
  const router = useRouter();
  const [events, setEvents] = useState<MemberEvent[]>(initialEvents);
  const [bookings, setBookings] = useState<MyEventBooking[]>(initialBookings);
  const [activeTab, setActiveTab] = useState<"confirmed" | "pending_payment" | "cancelled">("confirmed");
  const [message, setMessage] = useState<string>("");
  const [actionPending, setActionPending] = useState<boolean>(false);

  // Per-event guest state tracker: map of eventId -> array of guest names
  const [guestInputs, setGuestInputs] = useState<Record<string, string[]>>({});

  async function reloadData() {
    const supabase = createClient();
    const [eventsRes, bookingsRes] = await Promise.all([
      supabase.rpc("get_member_events"),
      supabase.rpc("get_my_event_bookings"),
    ]);
    if (eventsRes.data) setEvents(eventsRes.data);
    if (bookingsRes.data) setBookings(bookingsRes.data);
    router.refresh();
  }

  function handleAddGuest(eventId: string, maxGuests: number, availableSeats: number) {
    const current = guestInputs[eventId] || [];
    const maxAllowed = Math.min(maxGuests, availableSeats - 1);
    if (current.length >= maxAllowed) return;
    setGuestInputs({
      ...guestInputs,
      [eventId]: [...current, ""],
    });
  }

  function handleRemoveGuest(eventId: string, index: number) {
    const current = guestInputs[eventId] || [];
    setGuestInputs({
      ...guestInputs,
      [eventId]: current.filter((_, i) => i !== index),
    });
  }

  function handleGuestNameChange(eventId: string, index: number, name: string) {
    const current = [...(guestInputs[eventId] || [])];
    current[index] = name;
    setGuestInputs({
      ...guestInputs,
      [eventId]: current,
    });
  }

  async function handleBookingSubmit(event: FormEvent<HTMLFormElement>, eventItem: MemberEvent) {
    event.preventDefault();
    setActionPending(true);
    setMessage(`Reserving place for ${eventItem.title}…`);

    const rawGuests = guestInputs[eventItem.id] || [];
    const guests = rawGuests.map((g) => g.trim()).filter(Boolean);

    try {
      const supabase = createClient();
      const { error } = await supabase.rpc("create_event_booking", {
        p_event_id: eventItem.id,
        p_guest_names: guests,
      });

      if (error) throw new Error(error.message);

      setMessage("Booking places reserved. You can review your booking below.");
      setActiveTab("pending_payment");
      // Clear inputs for this event
      setGuestInputs({ ...guestInputs, [eventItem.id]: [] });
      await reloadData();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "We could not complete your booking.");
    } finally {
      setActionPending(false);
    }
  }

  async function handleCancelBooking(bookingId: string) {
    if (!confirm("Are you sure you want to cancel this booking?")) return;
    setActionPending(true);
    setMessage("Processing booking cancellation…");

    try {
      const supabase = createClient();
      const { data, error } = await supabase.rpc("cancel_event_booking", {
        p_booking_id: bookingId,
      });

      if (error) throw new Error(error.message);

      setMessage(
        data === "refund_pending"
          ? "Booking cancelled. Refund request is pending."
          : "Booking cancelled successfully."
      );
      await reloadData();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "Failed to cancel booking.");
    } finally {
      setActionPending(false);
    }
  }

  // Filtered bookings
  const confirmedBookings = bookings.filter((b) => b.status === "confirmed");
  const pendingBookings = bookings.filter((b) => b.status === "pending_payment");
  const cancelledBookings = bookings.filter((b) => b.status === "cancelled");

  const visibleBookings =
    activeTab === "confirmed"
      ? confirmedBookings
      : activeTab === "pending_payment"
      ? pendingBookings
      : cancelledBookings;

  return (
    <div>
      {message && (
        <p className="access-message form-message" style={{ marginBottom: "24px" }} aria-live="polite">
          {message}
        </p>
      )}

      <div className="event-booking-layout">
        {/* Main Events Catalogue */}
        <div className="member-event-list">
          {events.length === 0 ? (
            <p className="benefits-empty">No upcoming experiences are scheduled at this time.</p>
          ) : (
            events.map((eventItem) => {
              const guests = guestInputs[eventItem.id] || [];
              const seats = 1 + guests.length;
              const totalAmount =
                eventItem.pricing_model === "fixed_booking"
                  ? eventItem.price_paise
                  : eventItem.price_paise * seats;

              const isFull = eventItem.seats_available < 1;
              const guestLimit = eventItem.max_guests_per_member;
              const canAddGuests = guestLimit > 0 && guests.length < Math.min(guestLimit, eventItem.seats_available - 1);

              return (
                <article className="member-event-card" key={eventItem.id}>
                  <p className="eyebrow compact">{formatDate(eventItem.starts_at)}</p>
                  <h2>{eventItem.title}</h2>
                  <h3>{eventItem.venue}</h3>
                  <p>{eventItem.description}</p>

                  <div className="event-facts">
                    <span>
                      <small>Available Places</small>
                      <strong>
                        {eventItem.seats_available} of {eventItem.capacity}
                      </strong>
                    </span>
                    <span>
                      <small>Price</small>
                      <strong>
                        {formatRupees(eventItem.price_paise)}{" "}
                        {eventItem.pricing_model === "fixed_booking" ? "per booking" : "per attendee"}
                      </strong>
                    </span>
                    <span>
                      <small>Attendance</small>
                      <strong>
                        {guestLimit === 0
                          ? "Member only"
                          : `Up to ${guestLimit} ${guestLimit === 1 ? "guest" : "guests"}`}
                      </strong>
                    </span>
                    <span>
                      <small>Booking Cutoff</small>
                      <strong>{formatDate(eventItem.booking_closes_at)}</strong>
                    </span>
                  </div>

                  {/* Booking Form */}
                  <form
                    className="event-reserve-form"
                    onSubmit={(e) => handleBookingSubmit(e, eventItem)}
                  >
                    <div className="event-guest-control">
                      <div className="event-party-summary">
                        <strong>
                          {guests.length === 0
                            ? "Member only"
                            : `Member + ${guests.length} ${guests.length === 1 ? "guest" : "guests"}`}
                        </strong>
                        <span>Total {formatRupees(totalAmount)}</span>
                      </div>

                      {/* Dynamic Guest Name Rows */}
                      {guests.length > 0 && (
                        <div className="event-guest-list">
                          {guests.map((guestName, index) => (
                            <div className="event-guest-row" key={index}>
                              <label>
                                Guest {index + 1} Name
                                <input
                                  type="text"
                                  placeholder="Full legal name"
                                  required
                                  maxLength={100}
                                  value={guestName}
                                  onChange={(e) =>
                                    handleGuestNameChange(eventItem.id, index, e.target.value)
                                  }
                                />
                              </label>
                              <button
                                className="text-button danger-text"
                                type="button"
                                onClick={() => handleRemoveGuest(eventItem.id, index)}
                              >
                                Remove
                              </button>
                            </div>
                          ))}
                        </div>
                      )}

                      {canAddGuests && (
                        <button
                          className="text-button guest-add"
                          type="button"
                          onClick={() =>
                            handleAddGuest(eventItem.id, guestLimit, eventItem.seats_available)
                          }
                        >
                          + Add guest
                        </button>
                      )}
                    </div>

                    <button
                      className="button button-primary"
                      type="submit"
                      disabled={actionPending || isFull}
                    >
                      {isFull ? "Event Full" : actionPending ? "Reserving…" : "Reserve Booking"}
                    </button>
                  </form>
                </article>
              );
            })
          )}
        </div>

        {/* My Bookings Sidebar */}
        <aside>
          <h2>My Bookings</h2>

          <div className="booking-filters">
            <button
              className={`booking-filter ${activeTab === "confirmed" ? "active" : ""}`}
              type="button"
              onClick={() => setActiveTab("confirmed")}
            >
              Confirmed ({confirmedBookings.length})
            </button>
            <button
              className={`booking-filter ${activeTab === "pending_payment" ? "active" : ""}`}
              type="button"
              onClick={() => setActiveTab("pending_payment")}
            >
              Pending ({pendingBookings.length})
            </button>
            <button
              className={`booking-filter ${activeTab === "cancelled" ? "active" : ""}`}
              type="button"
              onClick={() => setActiveTab("cancelled")}
            >
              Cancelled ({cancelledBookings.length})
            </button>
          </div>

          <div className="my-bookings">
            {visibleBookings.length === 0 ? (
              <p className="benefits-empty" style={{ margin: 0 }}>
                No {activeTab.replace("_", " ")} bookings.
              </p>
            ) : (
              visibleBookings.map((booking) => (
                <article className="my-booking-card" key={booking.booking_id}>
                  <h3>{booking.title}</h3>
                  <p>
                    {formatDate(booking.starts_at)} · {booking.seats}{" "}
                    {booking.seats === 1 ? "place" : "places"}
                  </p>
                  {booking.guest_names && booking.guest_names.length > 0 && (
                    <p style={{ color: "var(--muted-dark)", fontSize: "11px" }}>
                      Guests: {booking.guest_names.join(", ")}
                    </p>
                  )}
                  <span className="status-pill">
                    {booking.status.replace("_", " ")} · {booking.payment_status.replace("_", " ")}
                  </span>

                  {booking.can_cancel && (
                    <button
                      className="text-button danger-text"
                      type="button"
                      disabled={actionPending}
                      onClick={() => handleCancelBooking(booking.booking_id)}
                      style={{ marginTop: "12px" }}
                    >
                      Cancel booking
                    </button>
                  )}
                </article>
              ))
            )}
          </div>
        </aside>
      </div>
    </div>
  );
}

