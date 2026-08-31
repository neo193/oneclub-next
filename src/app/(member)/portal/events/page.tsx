import type { Metadata } from "next";
import { EventBookingView } from "@/components/member/event-booking-view";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";
import type { MemberEvent, MyEventBooking } from "@/types/database";

export const metadata: Metadata = {
  title: "Member Events",
  description: "Private experiences and curated gatherings for One Club members.",
  robots: { index: false, follow: false },
};

export default async function MemberEventsPage() {
  await requireProfile("/portal/events");
  const supabase = await createClient();

  const [eventsRes, bookingsRes] = await Promise.all([
    supabase.rpc("get_member_events"),
    supabase.rpc("get_my_event_bookings"),
  ]);

  const events: MemberEvent[] = eventsRes.error || !eventsRes.data ? [] : eventsRes.data;
  const bookings: MyEventBooking[] = bookingsRes.error || !bookingsRes.data ? [] : bookingsRes.data;

  return (
    <section className="section member-page">
      <p className="eyebrow">
        <span />
        PRIVATE EXPERIENCES
      </p>
      <h1>Member Events</h1>
      <p className="page-intro">
        Reserve member and guest places for curated business meets, founder breakfasts, and exclusive community gatherings.
      </p>

      <EventBookingView initialEvents={events} initialBookings={bookings} />
    </section>
  );
}

