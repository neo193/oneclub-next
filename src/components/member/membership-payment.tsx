"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { useToast } from "@/components/ui/toast-provider";
import { reconcilePayment, startRazorpayPayment } from "@/lib/payments/razorpay";
import type { PurchasableMembershipTier } from "@/types/database";

const money = (paise: number) => new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 0 }).format(paise / 100);

export function MembershipPayment({ email, tiers, mode = "purchase" }: { email: string; tiers: PurchasableMembershipTier[]; mode?: "purchase" | "upgrade" }) {
  const [pendingTierId, setPendingTierId] = useState<string | null>(null);
  const { notify } = useToast();

  useEffect(() => {
    let active = true;
    reconcilePayment("membership")
      .then((recovered) => {
        if (active && recovered) {
          notify("A captured membership payment was recovered and confirmed.", "success");
          window.setTimeout(() => window.location.replace("/portal?payment=success"), 900);
        }
      })
      .catch(() => undefined);
    return () => { active = false; };
  }, [notify]);

  async function pay(tierId: string) {
    setPendingTierId(tierId);
    try {
      const completed = await startRazorpayPayment({ purpose: "membership", membershipTierId: tierId, email, onStatus: () => undefined });
      if (completed) {
        notify(mode === "upgrade" ? "Payment successful. Upgrading your membership…" : "Payment successful. Activating your membership…", "success");
        await new Promise((resolve) => window.setTimeout(resolve, 900));
        window.location.replace("/portal?payment=success");
      }
    } catch (error) {
      notify(error instanceof Error ? error.message : "We could not complete the payment.", "error");
    } finally {
      setPendingTierId(null);
    }
  }

  return (
    <div className={`membership-choice-grid${mode === "upgrade" ? " membership-upgrade-choice" : ""}`}>
      {tiers.map((tier) => {
        const price = tier.payable_paise ?? tier.price_paise;
        const unavailable = tier.places_remaining === 0;
        return <article className="membership-choice" key={tier.id}>
          <p className="eyebrow compact">{tier.name.toUpperCase()}</p>
          <h3>{money(price)}</h3>
          <p>{tier.description}</p>
          <small>{tier.validity_months ? `${tier.validity_months} months` : "Lifetime validity"}</small>
          {Boolean(tier.credit_paise) && <small>{money(tier.credit_paise || 0)} active-term credit applied</small>}
          {tier.places_remaining !== null && <small>{tier.places_remaining} places remaining</small>}
          <Button type="button" variant="secondary" disabled={pendingTierId !== null || unavailable} onClick={() => pay(tier.id)}>
            {pendingTierId === tier.id ? "Preparing payment…" : mode === "upgrade" ? `Upgrade to ${tier.name}` : `Choose ${tier.name}`}
          </Button>
        </article>;
      })}
    </div>
  );
}
