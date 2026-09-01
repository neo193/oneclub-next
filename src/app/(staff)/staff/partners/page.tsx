import type { Metadata } from "next";
import { PartnerManagementWorkspace } from "@/components/staff/partner-management-workspace";
import { requireStaffWorkspace } from "@/lib/staff/access";
import { createClient } from "@/lib/supabase/server";
import type { ManagedPartnerContent, ManagedPartnerProperty } from "@/types/database";

export const metadata: Metadata = { title: "Partners & Benefits", description: "Manage partner, benefit and property content.", robots: { index: false, follow: false } };

export default async function PartnerManagementPage() {
  await requireStaffWorkspace("/staff/partners");
  const supabase = await createClient();
  const [content, properties] = await Promise.all([supabase.rpc("list_partner_content_for_management"), supabase.rpc("list_partner_properties_for_management")]);
  const error = content.error || properties.error;
  return <section className="section staff-page"><p className="eyebrow"><span />PARTNER CONTENT</p><h1>Partners &<br /><em>benefits.</em></h1><p className="page-intro">Maintain each partner, its single member benefit and every property location. Reservation contacts are stored here for the future booking workflow.</p><PartnerManagementWorkspace initialRows={(content.data || []) as ManagedPartnerContent[]} initialProperties={(properties.data || []) as ManagedPartnerProperty[]} initialError={error ? "Partner content could not be loaded. Please retry." : ""} /></section>;
}
