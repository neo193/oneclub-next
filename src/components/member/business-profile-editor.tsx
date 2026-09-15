"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/lib/supabase/client";
import { useToast } from "@/components/ui/toast-provider";
import type { BusinessProfile } from "@/types/database";

export function BusinessProfileEditor({ profile }: { profile: BusinessProfile | null }) {
  const router = useRouter();
  const { notify } = useToast();
  const [pending, setPending] = useState(false);
  const [status, setStatus] = useState(profile?.status || "draft");

  async function save(form: HTMLFormElement, publish: boolean) {
    setPending(true);
    const values = new FormData(form);
    const interests = String(values.get("interests") || "").split(",").map((item) => item.trim()).filter(Boolean).slice(0, 20);
    const { error } = await createClient().rpc("save_my_business_profile", {
      p_display_name: String(values.get("display_name") || ""),
      p_business_name: String(values.get("business_name") || ""),
      p_role_title: String(values.get("role_title") || ""),
      p_industry: String(values.get("industry") || ""),
      p_city: String(values.get("city") || ""),
      p_summary: String(values.get("summary") || ""),
      p_interests: interests,
      p_website_url: String(values.get("website_url") || ""),
      p_linkedin_url: String(values.get("linkedin_url") || ""),
      p_publish: publish,
    });
    setPending(false);
    if (error) return notify(error.message, "error");
    setStatus(publish ? "published" : "draft");
    notify(publish ? "Business profile published to the member directory." : "Business profile saved as a private draft.", "success");
    router.refresh();
  }

  return <div className="business-profile-editor">
    <div className="business-profile-status"><span className={`status-pill ${status === "published" ? "state-active" : ""}`}>{status}</span><p>{status === "published" ? "Other directory members can discover this profile." : "This profile is private until you publish it."}</p></div>
    <form className="profile-form contact-form" onSubmit={(event) => { event.preventDefault(); void save(event.currentTarget, status === "published"); }}>
      <label>Directory display name<input name="display_name" defaultValue={profile?.display_name || ""} minLength={2} maxLength={100} placeholder="Your professional name" required /></label>
      <label>Business or organisation name<input name="business_name" defaultValue={profile?.business_name || ""} minLength={2} maxLength={120} required /></label>
      <label>Your role<input name="role_title" defaultValue={profile?.role_title || ""} minLength={2} maxLength={100} placeholder="Founder, Architect, Investor…" required /></label>
      <label>Industry<input name="industry" defaultValue={profile?.industry || ""} minLength={2} maxLength={100} placeholder="Hospitality, Technology, Finance…" required /></label>
      <label>Business location<input name="city" defaultValue={profile?.city || ""} maxLength={100} placeholder="Bengaluru" /></label>
      <label className="wide">What you do<textarea name="summary" defaultValue={profile?.summary || ""} minLength={20} maxLength={1000} placeholder="Describe your work, expertise and the kinds of connections you would value." required /></label>
      <label className="wide">Business interests and opportunities<small>Separate terms with commas. These help members discover you.</small><input name="interests" defaultValue={(profile?.interests || []).join(", ")} placeholder="Manufacturing, Partnerships, Export, Angel investing" /></label>
      <label>Business website<input name="website_url" type="url" defaultValue={profile?.website_url || ""} placeholder="https://example.com" /></label>
      <label>LinkedIn profile<input name="linkedin_url" type="url" defaultValue={profile?.linkedin_url || ""} placeholder="https://linkedin.com/in/…" /></label>
      <div className="wide business-profile-actions">
        <button className="button button-secondary" type="submit" disabled={pending}>{pending ? "Saving…" : status === "published" ? "Save changes" : "Save draft"}</button>
        {status === "published"
          ? <button className="button button-danger" type="button" disabled={pending} onClick={(event) => { if (event.currentTarget.form) void save(event.currentTarget.form, false); }}>Unpublish profile</button>
          : <button className="button button-primary" type="button" disabled={pending} onClick={(event) => { if (event.currentTarget.form) void save(event.currentTarget.form, true); }}>Publish profile</button>}
      </div>
    </form>
  </div>;
}
