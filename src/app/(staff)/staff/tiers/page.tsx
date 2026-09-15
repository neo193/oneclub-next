import type {Metadata} from "next";
import {TierManagementWorkspace} from "@/components/staff/tier-management-workspace";
import {requireStaffWorkspace} from "@/lib/staff/access";
import {createClient} from "@/lib/supabase/server";
export const metadata:Metadata={title:"Membership Tiers",robots:{index:false,follow:false}};
export default async function TierPage({searchParams}:{searchParams:Promise<{edit?:string}>}){await requireStaffWorkspace("/staff/tiers");const [{data,error},params]=await Promise.all([(await createClient()).rpc("list_membership_tiers_for_admin"),searchParams]);return <section className="section staff-page"><p className="eyebrow"><span/>ADMINISTRATOR CONTROL</p><h1>Membership<br/><em>tiers.</em></h1><p className="page-intro">Prepare future offers in draft and publish no more than two at a time.</p><TierManagementWorkspace initialTiers={data||[]} initialError={error?.message||""} initialEditId={params.edit}/></section>}
