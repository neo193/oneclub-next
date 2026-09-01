import type { Metadata } from "next";
import { MemberAdministrationWorkspace } from "@/components/staff/member-administration-workspace";
import { requireStaffWorkspace } from "@/lib/staff/access";
import { createClient } from "@/lib/supabase/server";
import type { ManagedMember } from "@/types/database";

export const metadata: Metadata = {
  title: "Member Administration",
  description: "Review member accounts and perform audited membership actions.",
  robots: { index: false, follow: false },
};

export default async function MemberAdministrationPage() {
  const profile = await requireStaffWorkspace("/staff/members");
  const supabase = await createClient();
  const { data, error } = await supabase.rpc("list_members_for_management");

  return (
    <section className="section staff-page">
      <p className="eyebrow"><span />MEMBER ADMINISTRATION</p>
      <h1>Member<br /><em>records.</em></h1>
      <p className="page-intro">Find accounts, review membership activity and perform authorised, audited changes.</p>
      <MemberAdministrationWorkspace
        initialMembers={(data || []) as ManagedMember[]}
        initialError={error ? "Member accounts could not be loaded. Please retry." : ""}
        isAdministrator={profile.app_role === "admin"}
      />
    </section>
  );
}
