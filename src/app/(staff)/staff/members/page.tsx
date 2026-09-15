import type { Metadata } from "next";
import { MemberAdministrationWorkspace } from "@/components/staff/member-administration-workspace";
import { requireStaffWorkspace } from "@/lib/staff/access";
import { createClient } from "@/lib/supabase/server";
import type { ManagedMember } from "@/types/database";
import { MembershipPricingControl } from "@/components/staff/membership-pricing-control";

export const metadata: Metadata = {
  title: "Member Administration",
  description: "Review member accounts and perform audited membership actions.",
  robots: { index: false, follow: false },
};

export default async function MemberAdministrationPage() {
  const profile = await requireStaffWorkspace("/staff/members");
  const supabase = await createClient();
  const [{ data, error }, slots] = await Promise.all([supabase.rpc("list_members_for_management"),profile.app_role === "admin" ? supabase.rpc("get_published_membership_slots_for_admin") : Promise.resolve({data:null,error:null})]);

  return (
    <section className="section staff-page">
      <p className="eyebrow"><span />MEMBER ADMINISTRATION</p>
      <h1>Member<br /><em>records.</em></h1>
      <p className="page-intro">Find accounts, review membership activity and perform authorised, audited changes.</p>
      {profile.app_role === "admin" && <MembershipPricingControl slots={slots.data || []} />}
      <MemberAdministrationWorkspace
        initialMembers={(data || []) as ManagedMember[]}
        initialError={error ? "Member accounts could not be loaded. Please retry." : ""}
        isAdministrator={profile.app_role === "admin"}
      />
    </section>
  );
}
