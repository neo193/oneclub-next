"use client";

import Link from "next/link";
import { useMemo, useState } from "react";
import type { MemberBenefit } from "@/types/database";

export function BenefitsCatalogue({
  benefits = [],
}: {
  benefits: MemberBenefit[];
}) {
  const [selectedCategory, setSelectedCategory] = useState<string>("");

  // Build unique sorted category list with counts
  const categories = useMemo(() => {
    const map = new Map<string, { label: string; count: number }>();
    benefits.forEach((item) => {
      const raw = String(item.category || "").trim();
      if (!raw) return;
      const key = raw.toLowerCase();
      const existing = map.get(key);
      map.set(key, {
        label: existing?.label || raw,
        count: (existing?.count || 0) + 1,
      });
    });
    return Array.from(map.entries()).sort((a, b) =>
      a[1].label.localeCompare(b[1].label, "en-IN", { sensitivity: "base" })
    );
  }, [benefits]);

  const filtered = useMemo(() => {
    if (!selectedCategory) return benefits;
    return benefits.filter(
      (item) => String(item.category || "").trim().toLowerCase() === selectedCategory
    );
  }, [benefits, selectedCategory]);

  return (
    <>
      {/* Reservation Guidance Banner */}
      <aside className="reservation-guidance portal-support-card" style={{ marginBottom: "32px" }}>
        <div>
          <p className="eyebrow compact">PARTNER VISITS & PRIVILEGES</p>
          <h2>Visiting partner properties</h2>
          <p>
            When visiting partner locations, present your digital member card in your portal. For property stays and reservations, contact Member Concierge to secure your preferred dates.
          </p>
        </div>
        <Link className="button button-primary" href="/portal/support?category=reservation_change">
          Contact Concierge
        </Link>
      </aside>

      {/* Category Filter Toolbar */}
      <div className="benefits-filter">
        <label>
          Browse by category
          <select
            value={selectedCategory}
            onChange={(e) => setSelectedCategory(e.target.value)}
          >
            <option value="">All categories ({benefits.length})</option>
            {categories.map(([key, category]) => (
              <option value={key} key={key}>
                {category.label} ({category.count})
              </option>
            ))}
          </select>
        </label>
        <p aria-live="polite">
          {filtered.length} {filtered.length === 1 ? "benefit" : "benefits"} shown
        </p>
      </div>

      {/* Catalogue Cards Grid */}
      <div className="benefits-catalogue">
        {filtered.length === 0 ? (
          <p className="benefits-empty">
            {benefits.length
              ? "No benefits are currently available in this category."
              : "No active member benefits are currently available."}
          </p>
        ) : (
          filtered.map((item, index) => (
            <article className="benefit-card" key={`${item.partner_name}-${item.benefit_title}-${index}`}>
              <p className="eyebrow compact">{item.category}</p>
              <h2>{item.benefit_title}</h2>
              <h3>{item.partner_name}</h3>
              {item.location && <small>{item.location}</small>}
              <p>{item.benefit_description}</p>
              <details>
                <summary>How to redeem</summary>
                <p>{item.redemption_instructions || "Present your active digital member card at the property."}</p>
                {item.terms && <p className="benefit-terms">Terms: {item.terms}</p>}
              </details>
            </article>
          ))
        )}
      </div>
    </>
  );
}

