"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { reconcilePayment, startRazorpayPayment } from "@/lib/payments/razorpay";
import { useToast } from "@/components/ui/toast-provider";

type PurchaseOptions = { annual_price_paise:number;founding_payable_paise:number;active_annual_credit_paise:number;founding_places_remaining:number;is_upgrade:boolean };
const money=(paise:number)=>new Intl.NumberFormat("en-IN",{style:"currency",currency:"INR",maximumFractionDigits:0}).format(paise/100);
export function MembershipPayment({ email, options }: { email: string; options:PurchaseOptions }) {
  const [pending, setPending] = useState(false);
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

  async function pay(plan:"annual"|"founding_lifetime") {
    setPending(true);
    try {
      const completed = await startRazorpayPayment({ purpose: "membership", membershipPlan:plan, email, onStatus: () => undefined });
      if (completed) {
        notify("Payment successful. Activating your membership…", "success");
        await new Promise((resolve) => window.setTimeout(resolve, 900));
        window.location.replace("/portal?payment=success");
      }
    } catch (error) {
      notify(error instanceof Error ? error.message : "We could not complete the payment.", "error");
    } finally {
      setPending(false);
    }
  }

  return (
    <div className="membership-choice-grid">
      {!options.is_upgrade&&<article className="membership-choice"><p className="eyebrow compact">ANNUAL</p><h3>{money(options.annual_price_paise)}</h3><p>One year of membership and all standard benefits.</p><Button type="button" variant="secondary" disabled={pending} onClick={()=>pay("annual")}>Choose annual</Button></article>}
      <article className="membership-choice featured"><p className="eyebrow compact">FOUNDING MEMBER</p><h3>{money(options.founding_payable_paise)}</h3><p>{options.is_upgrade?`${money(options.active_annual_credit_paise)} active-term credit applied. `:""}Lifetime membership and Founding Member events.</p><small>{options.founding_places_remaining} places remaining</small><Button type="button" variant="primary" disabled={pending||!options.founding_places_remaining} onClick={()=>pay("founding_lifetime")}>{options.is_upgrade?"Complete upgrade":"Choose Founding"}</Button></article>
    </div>
  );
}

