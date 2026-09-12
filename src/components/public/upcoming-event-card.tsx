"use client";

import { useEffect, useState } from "react";
import { ContentPanel } from "@/components/public/content-panel";
import { createClient } from "@/lib/supabase/client";

type UpcomingEvent = { title: string; venue: string; description: string };

export function UpcomingEventCard() {
  const [event, setEvent] = useState<UpcomingEvent | null>(null);
  const [status, setStatus] = useState<"loading" | "ready" | "error">("loading");

  useEffect(() => {
    const controller = new AbortController();
    createClient().rpc("get_public_upcoming_event")
      .abortSignal(controller.signal)
      .then(({ data, error }) => {
        if (controller.signal.aborted) return;
        if (error) {
          console.error("Public upcoming event query failed", error.message);
          setStatus("error");
          return;
        }
        setEvent(data?.[0] || null);
        setStatus("ready");
      });
    return () => controller.abort();
  }, []);

  return <ContentPanel wide>
    <span className="event-date">Upcoming Event{event ? ` · ${event.venue}` : ""}</span>
    <h2>{event?.title || (status === "loading" ? "Our next gathering" : status === "error" ? "Discover our member gatherings" : "More experiences coming soon")}</h2>
    <p aria-live="polite">{event?.description || (status === "loading" ? "Loading event details…" : status === "error" ? "Event details are temporarily unavailable. Please check again shortly." : "Our next gathering is being planned. Check back for the next published event.")}</p>
  </ContentPanel>;
}

