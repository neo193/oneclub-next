import Image from "next/image";
import type { Profile } from "@/types/database";

export function MemberCard({ profile }: { profile: Profile }) {
  const isFounding = Boolean(profile.founding_member_sequence);
  const designation = isFounding
    ? `FOUNDING MEMBER ${profile.founding_member_sequence ? `#${profile.founding_member_sequence}` : ""}`.trim()
    : "MEMBER";

  return (
    <article className="member-card">
      <Image
        src="/assets/oneclub-logo-gold-transparent.png"
        alt="One Club"
        width={105}
        height={60}
      />
      <p className="member-card-designation">{designation}</p>
      <h2>{profile.full_name || "Valued Member"}</h2>
      <div>
        <span>MEMBER ID</span>
        <strong>{profile.member_number || "PENDING"}</strong>
      </div>
      <small>Valid while membership is active · Non-transferable</small>
    </article>
  );
}

