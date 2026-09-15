"use client";

import { useEffect } from "react";
import { useToast } from "@/components/ui/toast-provider";

export function PaymentCompletionNotice() {
  const { notify } = useToast();

  useEffect(() => {
    notify("Payment successful. Your membership is active and your digital card is ready.", "success", 7000);
    window.history.replaceState(null, "", "/portal");
  }, [notify]);

  return null;
}

