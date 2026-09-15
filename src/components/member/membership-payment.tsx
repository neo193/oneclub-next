"use client";

import { useEffect, useState } from "react";
import { Button } from "@/components/ui/button";
import { reconcilePayment, startRazorpayPayment } from "@/lib/payments/razorpay";
import { useToast } from "@/components/ui/toast-provider";

export function MembershipPayment({ email }: { email: string }) {
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

  async function pay() {
    setPending(true);
    try {
      const completed = await startRazorpayPayment({ purpose: "membership", email, onStatus: () => undefined });
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
    <div>
      <Button type="button" variant="primary" disabled={pending} onClick={pay}>
        {pending ? "Opening secure checkout…" : "Pay ₹50,000"}
      </Button>
    </div>
  );
}

