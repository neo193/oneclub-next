"use client";

import { useEffect, useRef } from "react";
import { Button } from "@/components/ui/button";

export function ConfirmationDialog({
  open,
  title,
  children,
  confirmLabel,
  cancelLabel = "Go back",
  pendingLabel = "Processing…",
  pending = false,
  onConfirm,
  onClose,
}: {
  open: boolean;
  title: string;
  children: React.ReactNode;
  confirmLabel: string;
  cancelLabel?: string;
  pendingLabel?: string;
  pending?: boolean;
  onConfirm: () => void;
  onClose: () => void;
}) {
  const ref = useRef<HTMLDialogElement>(null);

  useEffect(() => {
    const dialog = ref.current;
    if (!dialog) return;
    if (open && !dialog.open) dialog.showModal();
    if (!open && dialog.open) dialog.close();
  }, [open]);

  return (
    <dialog ref={ref} className="confirmation-dialog" onCancel={(event) => { event.preventDefault(); onClose(); }}>
      <div className="confirmation-dialog-panel">
        <p className="eyebrow compact">PLEASE CONFIRM</p>
        <h2>{title}</h2>
        <div className="confirmation-dialog-copy">{children}</div>
        <div className="confirmation-dialog-actions">
          <Button type="button" variant="secondary" disabled={pending} onClick={onClose}>{cancelLabel}</Button>
          <Button type="button" variant="danger" disabled={pending} onClick={onConfirm}>
            {pending ? pendingLabel : confirmLabel}
          </Button>
        </div>
      </div>
    </dialog>
  );
}
