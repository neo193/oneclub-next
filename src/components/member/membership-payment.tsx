"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { reconcilePayment, startRazorpayPayment } from "@/lib/payments/razorpay";

export function MembershipPayment({ email }: { email: string }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState("");

  useEffect(() => {
    let active = true;
    reconcilePayment("membership")
      .then((recovered) => {
        if (active && recovered) {
          setMessage("A captured membership payment was recovered and confirmed.");
          router.refresh();
        }
      })
      .catch(() => undefined);
    return () => { active = false; };
  }, [router]);

  async function pay() {
    setPending(true);
    try {
      const completed = await startRazorpayPayment({ purpose: "membership", email, onStatus: setMessage });
      if (completed) router.refresh();
    } catch (error) {
      setMessage(error instanceof Error ? error.message : "We could not complete the payment.");
    } finally {
      setPending(false);
    }
  }

  return (
    <div>
      <Button type="button" variant="primary" disabled={pending} onClick={pay}>
        {pending ? "Opening secure checkout…" : "Pay ₹50,000"}
      </Button>
      {message && <p className="form-message" aria-live="polite">{message}</p>}
    </div>
  );
}
