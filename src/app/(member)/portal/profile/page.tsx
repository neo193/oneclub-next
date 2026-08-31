import type { Metadata } from "next";
import { ProfileEditor } from "@/components/member/profile-editor";
import { requireProfile } from "@/lib/auth/profile";
import { createClient } from "@/lib/supabase/server";

export const metadata: Metadata = {
  title: "Member Profile",
  description: "Manage your One Club member details and preferences.",
  robots: { index: false, follow: false },
};

export default async function MemberProfilePage() {
  const profile = await requireProfile("/portal/profile");
  const supabase = await createClient();
  const { data: claimsData } = await supabase.auth.getClaims();
  const userEmail = String(claimsData?.claims?.email || "");

  return (
    <section className="section member-page">
      <p className="eyebrow">
        <span />
        MEMBERSHIP PREFERENCES
      </p>
      <h1>My Profile</h1>
      <p className="page-intro">
        Keep your personal details, profession, and interests current so we can tailor experiences and partner privileges to your preferences.
      </p>

      <ProfileEditor profile={profile} userEmail={userEmail} />
    </section>
  );
}

