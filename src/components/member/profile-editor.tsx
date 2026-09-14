"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { ConfirmationDialog } from "@/components/ui/confirmation-dialog";
import type { AccountDeletionEligibility } from "@/types/database";
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
  const [deletion, setDeletion] = useState<"confirm" | "bookings" | "refunds" | null>(null);
  const [eligibility, setEligibility] = useState<AccountDeletionEligibility | null>(null);
  const [deletePhrase, setDeletePhrase] = useState("");
  const [password, setPassword] = useState("");

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

  async function beginDeletion() {
    setPending(true);setMessage("Checking your account…");
    const {data,error}=await createClient().rpc("get_account_deletion_eligibility");
    setPending(false);
    if(error){setMessage(error.message);return;}
    const result=data as AccountDeletionEligibility;setEligibility(result);setMessage("");
    setDeletion(result.allowed?"confirm":result.block_reason==="pending_refunds"?"refunds":"bookings");
  }

  async function deleteAccount() {
    if(deletePhrase!=="DELETE MY ACCOUNT"){setMessage("Type DELETE MY ACCOUNT exactly as shown.");return;}
    if(password.length<8){setMessage("Enter your current password.");return;}
    setPending(true);setMessage("Permanently deleting your account…");
    const {data,error}=await createClient().functions.invoke("account-deletion",{body:{password}});
    let errorMessage=data?.message||error?.message||"Account deletion failed.";
    if(error&&"context" in error&&error.context instanceof Response){
      const body=await error.context.clone().json().catch(()=>null);
      if(body?.message)errorMessage=body.message;
    }
    if(error||!data?.deleted){setPending(false);setMessage(errorMessage);return;}
    router.replace("/login?account=deleted");
    router.refresh();
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
      <section className="account-deletion-panel">
        <p className="eyebrow compact">PERMANENT ACCOUNT ACTION</p><h2>Delete My Account</h2>
        <p>This removes your access and personal profile information. Booking and financial records are retained anonymously.</p>
        <button className="button button-danger" type="button" disabled={pending} onClick={beginDeletion}>Delete My Account</button>
      </section>
      <ConfirmationDialog open={deletion==="bookings"} title="Account deletion is unavailable" confirmLabel="Close" cancelLabel="View bookings" onClose={()=>router.push("/portal/events")} onConfirm={()=>setDeletion(null)}>
        <p>Your account has {eligibility?.upcoming_event_bookings||0} upcoming event booking(s) and {eligibility?.upcoming_property_bookings||0} active property booking(s). Cancel or complete them before deleting your account.</p>
      </ConfirmationDialog>
      <ConfirmationDialog open={deletion==="refunds"} title="A refund still needs attention" confirmLabel="Contact support" cancelLabel="Go back" onClose={()=>setDeletion(null)} onConfirm={()=>router.push(`/portal/support?accountDeletion=${encodeURIComponent(eligibility?.support_context||"")}`)}>
        <p>{eligibility?.pending_refunds||0} refund(s) are unresolved. The membership desk will expedite them before account deletion can continue.</p>
      </ConfirmationDialog>
      <ConfirmationDialog open={deletion==="confirm"} title="Permanently delete your account?" confirmLabel="Delete account" pending={pending} pendingLabel="Deleting…" onClose={()=>setDeletion(null)} onConfirm={deleteAccount}>
        <p>This cannot be undone. Your original email will be released for a new account, but the new account will not inherit this account&apos;s history.</p>
        <label className="deletion-confirm-field">Current password<input type="password" autoComplete="current-password" value={password} onChange={event=>setPassword(event.target.value)} /></label>
        <label className="deletion-confirm-field">Type DELETE MY ACCOUNT<input value={deletePhrase} autoComplete="off" onChange={event=>setDeletePhrase(event.target.value)} /></label>
        {message&&<p className="form-message" aria-live="polite">{message}</p>}
      </ConfirmationDialog>
    </div>
  );
}

