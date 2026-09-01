"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import type { MemberBenefitCatalogueItem } from "@/types/database";

export function BenefitsCatalogue({ benefits = [] }: { benefits: MemberBenefitCatalogueItem[] }) {
  const [selectedCategory, setSelectedCategory] = useState("");
  const [query, setQuery] = useState("");
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const categories = useMemo(() => {
    const map = new Map<string, { label: string; count: number }>();
    benefits.forEach((item) => {
      const label = item.category.trim(); const key = label.toLowerCase(); const current = map.get(key);
      map.set(key, { label: current?.label || label, count: (current?.count || 0) + 1 });
    });
    return [...map.entries()].sort((a, b) => a[1].label.localeCompare(b[1].label, "en-IN", { sensitivity: "base" }));
  }, [benefits]);
  const filtered = useMemo(() => {
    const search = query.trim().toLowerCase();
    return benefits.filter((item) => {
      if (selectedCategory && item.category.trim().toLowerCase() !== selectedCategory) return false;
      if (!search) return true;
      return [item.partner_name, item.benefit_title, item.category, item.benefit_description, ...item.locations.flatMap((location) => [location.name, location.address])].some((value) => value?.toLowerCase().includes(search));
    });
  }, [benefits, query, selectedCategory]);
  function toggle(key: string) { setExpanded((current) => { const next = new Set(current); if (next.has(key)) next.delete(key); else next.add(key); return next; }); }

  return <>
    <aside className="reservation-guidance portal-support-card benefits-guidance-next"><div><p className="eyebrow compact">PARTNER VISITS & PRIVILEGES</p><h2>Visiting partner properties</h2><p>Present your digital member card when visiting a partner. For property stays and reservations, contact Member Concierge to secure your preferred dates.</p></div><Link className="button button-primary" href="/portal/support?category=reservation_change">Contact Concierge</Link></aside>
    <div className="benefits-filter"><label>Browse by category<select value={selectedCategory} onChange={(event) => setSelectedCategory(event.target.value)}><option value="">All categories ({benefits.length})</option>{categories.map(([key, category]) => <option value={key} key={key}>{category.label} ({category.count})</option>)}</select></label><label className="benefits-search-next">Search partners and locations<input type="search" value={query} onChange={(event) => setQuery(event.target.value)} placeholder="Search by property, benefit or location" /></label><p aria-live="polite">{filtered.length} {filtered.length === 1 ? "benefit" : "benefits"} shown</p></div>
    <div className="benefits-catalogue">{filtered.length === 0 ? <p className="benefits-empty">{benefits.length ? "No partner benefits match your search." : "No active member benefits are currently available."}</p> : filtered.map((item, index) => { const key = `${item.partner_name}-${item.benefit_title}-${index}`; const isMultiLocation = item.locations.length > 0; const hasOverflow = item.locations.length > 5; const isExpanded = expanded.has(key); return <article className={`benefit-card ${isMultiLocation ? "is-multi-location" : "is-single-location"}`} key={key}><div className="benefit-card-main-next"><p className="eyebrow compact">{item.category}{!isMultiLocation && item.location ? <><span className="benefit-meta-divider-next">·</span>{item.location}</> : null}</p><h2>{item.benefit_title}</h2><h3>{item.partner_name}</h3><p>{item.benefit_description}</p><details><summary>How to redeem</summary><p>{item.redemption_instructions || "Present your active digital member card at the property."}</p>{item.terms && <p className="benefit-terms">Terms: {item.terms}</p>}</details></div>{isMultiLocation && <section className="benefit-locations-next"><div className="benefit-location-heading-next"><p className="eyebrow compact">AVAILABLE LOCATIONS · {item.locations.length}</p>{hasOverflow && <button type="button" onClick={() => toggle(key)}>{isExpanded ? "Show fewer" : "Show all"}</button>}</div><div className={`benefit-location-grid-next ${hasOverflow && !isExpanded ? "is-collapsed" : ""}`}>{item.locations.map((location) => <div className="benefit-location-next" key={location.id}><strong>{location.name}</strong>{location.address && location.address !== location.name && <small>{location.address}</small>}</div>)}</div></section>}</article>; })}</div>
  </>;
}
