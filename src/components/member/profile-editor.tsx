"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import type { Profile } from "@/types/database";

export function ProfileEditor({ profile, userEmail }: { profile: Profile; userEmail: string }) {
  const router = useRouter();
  const [fullName, setFullName] = useState(profile.full_name || "");
  const [phone, setPhone] = useState(profile.phone || "");
  const [birthday, setBirthday] = useState(profile.birthday || "");
  const [locality, setLocality] = useState(profile.locality || "");
  const [profession, setProfession] = useState(profile.profession || "");
  const [industry, setIndustry] = useState(profile.industry || "");
  const [interests, setInterests] = useState((profile.interests || []).join(", "));
  const [message, setMessage] = useState("");
  const [pending, setPending] = useState(false);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setMessage("Saving profile…");

    const interestsArray = interests
      .split(",")
      .map((item) => item.trim())
      .filter(Boolean)
      .slice(0, 20);

    try {
      const supabase = createClient();
      const { error } = await supabase
        .from("profiles")
        .update({
          full_name: fullName.trim() || null,
          phone: phone.trim() || null,
          birthday: birthday || null,
          locality: locality.trim() || null,
          profession: profession.trim() || null,
          industry: industry.trim() || null,
          interests: interestsArray.length ? interestsArray : null,
        })
        .eq("id", profile.id);

      if (error) throw new Error(error.message);

      setMessage("Profile saved successfully.");
      router.refresh();
    } catch (err) {
      setMessage(err instanceof Error ? err.message : "Failed to update profile.");
    } finally {
      setPending(false);
    }
  }

  return (
    <div>
      {/* Locked / Verified Information */}
      <div className="locked-fields" style={{ marginBottom: "28px" }}>
        <div>
          <small>Registered Email</small>
          <strong>{userEmail || "—"}</strong>
        </div>
        <div>
          <small>Member ID</small>
          <strong>{profile.member_number || "Not assigned"}</strong>
        </div>
        <div>
          <small>Membership Tier</small>
          <strong>{profile.founding_member_sequence ? `Founding Member #${profile.founding_member_sequence}` : "Member"}</strong>
        </div>
        <div>
          <small>Account Status</small>
          <strong style={{ textTransform: "capitalize" }}>{profile.membership_state.replace("_", " ")}</strong>
        </div>
      </div>

      {/* Profile Form */}
      <form className="profile-form contact-form" onSubmit={handleSubmit}>
        <label>
          Full Legal Name
          <input
            type="text"
            required
            maxLength={100}
            value={fullName}
            onChange={(e) => setFullName(e.target.value)}
          />
        </label>

        <label>
          Phone Number
          <input
            type="tel"
            maxLength={30}
            placeholder="+91"
            value={phone}
            onChange={(e) => setPhone(e.target.value)}
          />
        </label>

        <label>
          Date of Birth
          <input
            type="date"
            value={birthday}
            onChange={(e) => setBirthday(e.target.value)}
          />
        </label>

        <label>
          City / Locality
          <input
            type="text"
            maxLength={100}
            placeholder="e.g. Indiranagar, Bengaluru"
            value={locality}
            onChange={(e) => setLocality(e.target.value)}
          />
        </label>

        <label>
          Profession / Designation
          <input
            type="text"
            maxLength={100}
            placeholder="e.g. Founder & CEO"
            value={profession}
            onChange={(e) => setProfession(e.target.value)}
          />
        </label>

        <label>
          Industry
          <input
            type="text"
            maxLength={100}
            placeholder="e.g. Technology / Venture Capital"
            value={industry}
            onChange={(e) => setIndustry(e.target.value)}
          />
        </label>

        <label className="wide">
          Interests & Passions
          <small style={{ color: "var(--muted-dark)", marginBottom: "6px", display: "block" }}>
            Separate with commas (e.g. Tennis, Horology, Specialty Coffee, Startups)
          </small>
          <input
            type="text"
            placeholder="Interests"
            value={interests}
            onChange={(e) => setInterests(e.target.value)}
          />
        </label>

        <div className="wide" style={{ display: "flex", alignItems: "center", gap: "16px", marginTop: "12px" }}>
          <button className="button button-primary" type="submit" disabled={pending}>
            {pending ? "Saving…" : "Save Profile"}
          </button>
          <p className="form-message" aria-live="polite" style={{ margin: 0 }}>
            {message}
          </p>
        </div>
      </form>
    </div>
  );
}

