"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { Button } from "@/components/ui/button";
import { reconcilePayment, startRazorpayPayment } from "@/lib/payments/razorpay";
import { useToast } from "@/components/ui/toast-provider";

export function MembershipPayment({ email }: { email: string }) {
  const router = useRouter();
  const [pending, setPending] = useState(false);
  const { notify } = useToast();

  useEffect(() => {
    let active = true;
    reconcilePayment("membership")
      .then((recovered) => {
        if (active && recovered) {
          notify("A captured membership payment was recovered and confirmed.", "success");
          router.refresh();
        }
      })
      .catch(() => undefined);
    return () => { active = false; };
  }, [notify, router]);

  async function pay() {
    setPending(true);
    try {
      const completed = await startRazorpayPayment({ purpose: "membership", email, onStatus: (message) => {
        if (/verified successfully/i.test(message)) notify(message, "success");
      } });
      if (completed) router.refresh();
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

