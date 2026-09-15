"use client";

import { useState, type FormEvent } from "react";
import { createClient } from "@/lib/supabase/client";
import { useToast } from "@/components/ui/toast-provider";
import type { BusinessDirectoryResult } from "@/types/database";

export function BusinessDirectory({ initialResults }: { initialResults: BusinessDirectoryResult[] }) {
  const [results, setResults] = useState(initialResults);
  const [pending, setPending] = useState(false);
  const { notify } = useToast();

  async function search(event: FormEvent<HTMLFormElement>) {
    event.preventDefault(); setPending(true);
    const values = new FormData(event.currentTarget);
    const { data, error } = await createClient().rpc("search_business_directory", {
      p_query: String(values.get("query") || ""), p_industry: String(values.get("industry") || ""),
      p_role: String(values.get("role") || ""), p_interest: String(values.get("interest") || ""), p_limit: 50,
    });
    setPending(false);
    if (error) return notify(error.message, "error");
    setResults(data || []);
  }

  async function clear(form: HTMLFormElement) {
    form.reset();
    setPending(true);
    const { data, error } = await createClient().rpc("search_business_directory", { p_limit: 50 });
    setPending(false);
    if (error) return notify(error.message, "error");
    setResults(data || []);
  }

  return <div className="business-directory-workspace">
    <form className="directory-search" onSubmit={search}>
      <label className="wide">Search directory<input name="query" placeholder="Name, business, expertise or opportunity" /></label>
      <label>Industry<input name="industry" placeholder="e.g. Hospitality" /></label>
      <label>Role<input name="role" placeholder="e.g. Founder" /></label>
      <label>Interest<input name="interest" placeholder="e.g. Export" /></label>
      <div className="directory-search-actions">
        <button className="button button-primary" disabled={pending}>{pending ? "Searching…" : "Search members"}</button>
        <button className="button button-secondary" type="button" disabled={pending} onClick={(event) => { if (event.currentTarget.form) void clear(event.currentTarget.form); }}>Clear filters</button>
      </div>
    </form>
    <p className="directory-result-count">{results.length} {results.length === 1 ? "profile" : "profiles"}</p>
    <div className="business-directory-grid">{results.map((item) => <article className="business-directory-card" key={item.member_id}>
      <p className="eyebrow compact">{item.industry}</p><h2>{item.member_name || item.business_name}</h2>
      <h3>{item.role_title} · {item.business_name}</h3>{item.city && <small>{item.city}</small>}<p>{item.summary}</p>
      {item.interests.length > 0 && <div className="directory-tags">{item.interests.map((interest) => <span key={interest}>{interest}</span>)}</div>}
      <div className="directory-links">{item.website_url && <a href={item.website_url} target="_blank" rel="noreferrer">Website</a>}{item.linkedin_url && <a href={item.linkedin_url} target="_blank" rel="noreferrer">LinkedIn</a>}</div>
    </article>)}</div>
    {!results.length && <p className="staff-empty">No published business profiles match this search.</p>}
  </div>;
}
