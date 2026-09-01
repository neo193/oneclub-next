import type { Metadata } from "next";
import { EventManagementWorkspace } from "@/components/staff/event-management-workspace";
import { requireStaffWorkspace } from "@/lib/staff/access";
import { createClient } from "@/lib/supabase/server";
import type { ManagedEvent } from "@/types/database";

export const metadata: Metadata = { title: "Event Management", description: "Manage the One Club event catalogue and complimentary bookings.", robots: { index: false, follow: false } };

export default async function EventManagementPage() {
  const profile = await requireStaffWorkspace("/staff/events");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_events_for_management");
  return <section className="section staff-page"><p className="eyebrow"><span />EVENT MANAGEMENT</p><h1>Private<br /><em>experiences.</em></h1><p className="page-intro">Create and maintain the private event catalogue. Published future events appear immediately to active members.</p><EventManagementWorkspace initialEvents={(data || []) as ManagedEvent[]} initialError={error ? "Events could not be loaded. Please retry." : ""} isAdministrator={profile.app_role === "admin"} /></section>;
}
