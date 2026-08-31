"use client";

import { createClient } from "@/lib/supabase/client";
import { publicSupabaseEnvironment } from "@/lib/env/public";

type PaymentPurpose = "membership" | "event";

type CheckoutResult = {
  razorpay_order_id: string;
  razorpay_payment_id: string;
  razorpay_signature: string;
};

type PaymentOrder = {
  attempt_id: string;
  key_id: string;
  order_id: string;
  amount: number;
  currency: string;
  description: string;
};

type RazorpayCheckout = {
  open(): void;
  on(name: "payment.failed", callback: (response: { error?: { description?: string } }) => void): void;
};

declare global {
  interface Window {
    Razorpay?: new (options: Record<string, unknown>) => RazorpayCheckout;
  }
}

let scriptPromise: Promise<void> | null = null;

function loadCheckout() {
  if (window.Razorpay) return Promise.resolve();
  if (scriptPromise) return scriptPromise;
  scriptPromise = new Promise<void>((resolve, reject) => {
    const script = document.createElement("script");
    script.src = "https://checkout.razorpay.com/v1/checkout.js";
    script.async = true;
    script.onload = () => resolve();
    script.onerror = () => reject(new Error("Razorpay Checkout could not be loaded."));
    document.head.appendChild(script);
  });
  return scriptPromise;
}

export async function callRazorpayService(body: Record<string, unknown>) {
  const supabase = createClient();
  const { data, error } = await supabase.auth.getSession();
  if (error || !data.session) throw new Error("Your session has expired. Please sign in again.");
  const environment = publicSupabaseEnvironment();
  const response = await fetch(`${environment.url}/functions/v1/razorpay-payments`, {
    method: "POST",
    headers: {
      apikey: environment.anonKey,
      Authorization: `Bearer ${data.session.access_token}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const result = (await response.json().catch(() => null)) as Record<string, unknown> | null;
  if (!response.ok) throw new Error(String(result?.message || "Payment service failed."));
  return result || {};
}

export async function reconcilePayment(purpose: PaymentPurpose, bookingId?: string) {
  const result = await callRazorpayService({ action: "reconcile", purpose, booking_id: bookingId || null });
  return result.recovered === true;
}

export async function startRazorpayPayment({
  purpose,
  bookingId,
  email,
  onStatus,
}: {
  purpose: PaymentPurpose;
  bookingId?: string;
  email?: string;
  onStatus: (message: string) => void;
}) {
  await loadCheckout();
  if (!window.Razorpay) throw new Error("Razorpay Checkout could not be loaded.");
  onStatus("Creating secure payment order…");
  const order = (await callRazorpayService({
    action: "create",
    purpose,
    booking_id: bookingId || null,
  })) as PaymentOrder;

  return new Promise<boolean>((resolve, reject) => {
    const checkout = new window.Razorpay!({
      key: order.key_id,
      amount: order.amount,
      currency: order.currency,
      name: "One Club",
      description: order.description,
      order_id: order.order_id,
      prefill: { email: email || "" },
      theme: { color: "#b99a62" },
      handler: async (result: CheckoutResult) => {
        onStatus("Verifying payment securely…");
        try {
          await callRazorpayService({
            action: "verify",
            attempt_id: order.attempt_id,
            razorpay_order_id: result.razorpay_order_id,
            razorpay_payment_id: result.razorpay_payment_id,
            razorpay_signature: result.razorpay_signature,
          });
          onStatus("Payment verified successfully.");
          resolve(true);
        } catch (error) {
          onStatus("Payment was captured; checking its final status…");
          try {
            if (await reconcilePayment(purpose, bookingId)) {
              onStatus("Payment recovered and confirmed.");
              resolve(true);
            } else reject(error);
          } catch {
            reject(error);
          }
        }
      },
      modal: {
        ondismiss: () => {
          onStatus("Payment window closed. You can try again while the reservation remains valid.");
          resolve(false);
        },
      },
    });
    checkout.on("payment.failed", (response) => {
      reject(new Error(response.error?.description || "The payment failed."));
    });
    checkout.open();
  });
}
