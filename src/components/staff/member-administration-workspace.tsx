"use client";

import { useEffect, useMemo, useRef, useState } from "react";
import { ConfirmationDialog } from "@/components/ui/confirmation-dialog";
import { createClient } from "@/lib/supabase/client";
import type { ManagedMember, MemberAdminRecord, MembershipControl } from "@/types/database";

const PAGE_SIZE = 5;
type AccessAction = "suspend" | "reactivate";
type MembershipAction = "cancel" | "revoke_offer" | "expiry" | "complimentary" | "restore_cancelled_offer" | "restore_expired_complimentary" | "reopen_expired_payment" | "offline";
type Confirmation = { title: string; label: string; warning: string; run: () => Promise<void> } | null;
type AccessDraft = { member: ManagedMember; action: AccessAction } | null;

const label = (value: string | null | undefined) => String(value || "none").replaceAll("_", " ").replaceAll(".", " · ").replace(/\b\w/g, (letter) => letter.toUpperCase());
const dateTime = (value: string | null | undefined) => value ? new Intl.DateTimeFormat("en-IN", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value)) : "Not available";
const localInputDate = (value?: string | null) => { const date = value ? new Date(value) : new Date(); return new Date(date.getTime() - date.getTimezoneOffset() * 60000).toISOString().slice(0, 16); };
const csvCell = (value: unknown) => { let text = String(value ?? ""); if (/^[=+\-@]/.test(text)) text = `'${text}`; return `"${text.replaceAll('"', '""')}"`; };

function DetailDialog({ open, onClose, children }: { open: boolean; onClose: () => void; children: React.ReactNode }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => { const dialog = ref.current; if (!dialog) return; if (open && !dialog.open) dialog.showModal(); if (!open && dialog.open) dialog.close(); }, [open]);
  return <dialog ref={ref} className="member-detail-dialog-next" onCancel={(event) => { event.preventDefault(); onClose(); }}>{children}</dialog>;
}

function AccessReasonDialog({ draft, onClose, onContinue }: { draft: AccessDraft; onClose: () => void; onContinue: (reason: string) => void }) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => { const dialog = ref.current; if (!dialog) return; if (draft && !dialog.open) dialog.showModal(); if (!draft && dialog.open) dialog.close(); }, [draft]);
  return <dialog ref={ref} className="member-access-dialog-next" onCancel={(event) => { event.preventDefault(); onClose(); }}><form onSubmit={(event) => { event.preventDefault(); const reason = String(new FormData(event.currentTarget).get("reason") || "").trim(); if (reason.length >= 3) onContinue(reason); }}><p className="eyebrow compact">AUDITED ACCESS CHANGE</p><h2>{draft?.action === "suspend" ? "Suspend member" : "Reactivate member"}</h2><p>{draft?.member.full_name || draft?.member.email} · {draft?.member.member_number || "No member ID"}</p><label>Mandatory reason<textarea name="reason" minLength={3} maxLength={300} autoFocus required /></label><div><button className="button button-secondary" type="button" onClick={onClose}>Go back</button><button className="button button-primary" type="submit">Review change</button></div></form></dialog>;
}

export function MemberAdministrationWorkspace({ initialMembers, initialError, isAdministrator }: { initialMembers: ManagedMember[]; initialError: string; isAdministrator: boolean }) {
  const [members, setMembers] = useState(initialMembers);
  const [message, setMessage] = useState(initialError || `${initialMembers.length} member accounts loaded.`);
  const [query, setQuery] = useState("");
  const [stateFilter, setStateFilter] = useState("all");
  const [sort, setSort] = useState("name");
  const [page, setPage] = useState(1);
  const [selected, setSelected] = useState<ManagedMember | null>(null);
  const [record, setRecord] = useState<MemberAdminRecord | null>(null);
  const [control, setControl] = useState<MembershipControl | null>(null);
  const [detailMessage, setDetailMessage] = useState("");
  const [pending, setPending] = useState(false);
  const [confirmation, setConfirmation] = useState<Confirmation>(null);
  const [accessDraft, setAccessDraft] = useState<AccessDraft>(null);

  const filtered = useMemo(() => {
    const search = query.trim().toLocaleLowerCase();
    const rows = members.filter((member) => {
      const haystack = [member.full_name, member.email, member.member_number].filter(Boolean).join(" ").toLocaleLowerCase();
      return (!search || haystack.includes(search)) && (stateFilter === "all" || member.membership_state === stateFilter);
    });
    const compare = (a: string | null | undefined, b: string | null | undefined) => String(a || "").localeCompare(String(b || ""), undefined, { sensitivity: "base", numeric: true });
    return rows.sort((a, b) => sort === "name-desc" ? compare(b.full_name || b.email, a.full_name || a.email) : sort === "member-number" ? compare(a.member_number || "ZZZ", b.member_number || "ZZZ") : sort === "state" ? compare(a.membership_state, b.membership_state) || compare(a.full_name, b.full_name) : compare(a.full_name || a.email, b.full_name || b.email));
  }, [members, query, sort, stateFilter]);

  const pages = Math.max(1, Math.ceil(filtered.length / PAGE_SIZE));
  const currentPage = Math.min(page, pages);
  const visible = filtered.slice((currentPage - 1) * PAGE_SIZE, currentPage * PAGE_SIZE);

  async function loadMembers(announce = true) {
    const { data, error } = await createClient().rpc("list_members_for_management");
    if (error) throw new Error(error.message);
    setMembers(data || []);
    if (announce) setMessage(`${data?.length || 0} member accounts loaded.`);
  }

  async function loadRecord(member: ManagedMember) {
    setSelected(member); setRecord(null); setControl(null); setDetailMessage("Loading member record…");
    const supabase = createClient();
    const { data, error } = await supabase.rpc("get_member_admin_record", { p_member_id: member.id });
    if (error) { setDetailMessage(error.message); return; }
    const nextRecord = data as unknown as MemberAdminRecord;
    setRecord(nextRecord); setDetailMessage("");
    if (isAdministrator) {
      const membership = await supabase.rpc("get_member_membership_control", { p_member_id: member.id });
      if (membership.error) setDetailMessage(membership.error.message);
      else setControl(membership.data as unknown as MembershipControl);
    }
  }

  async function refreshSelected(success: string) {
    await loadMembers(false);
    if (selected) await loadRecord(selected);
    setMessage(success); setDetailMessage(success);
  }

  function confirmAccess(member: ManagedMember, action: AccessAction, reason: string) {
    setConfirmation({
      title: action === "suspend" ? "Suspend member access?" : "Reactivate member access?",
      label: action === "suspend" ? "Suspend member" : "Reactivate member",
      warning: action === "suspend" ? `This immediately prevents ${member.full_name || member.email} from using member access until reactivated.` : `This restores member access for ${member.full_name || member.email}.`,
      run: async () => {
        const { error } = await createClient().rpc("set_member_access_state", { p_member_id: member.id, p_action: action, p_reason: reason });
        if (error) throw new Error(error.message);
        await loadMembers(false);
        setMessage(`${member.full_name || member.email} has been ${action === "suspend" ? "suspended" : "reactivated"}.`);
      },
    });
  }

  async function runConfirmation() {
    if (!confirmation) return;
    setPending(true);
    try { await confirmation.run(); setConfirmation(null); }
    catch (error) { setMessage(error instanceof Error ? error.message : "The action could not be completed."); }
    finally { setPending(false); }
  }

  async function exportCsv() {
    if (!filtered.length) { setMessage("There are no matching members to export."); return; }
    setPending(true); setMessage("Preparing the filtered member directory…");
    try {
      const { data, error } = await createClient().rpc("export_members_for_management");
      if (error) throw new Error(error.message);
      const exportRows = (data || []) as unknown as (ManagedMember & { account_created_at?: string; locality?: string; profession?: string; industry?: string })[];
      const byId = new Map(exportRows.map((row) => [row.id, row]));
      const selectedRows = filtered.map((member) => ({ ...member, ...byId.get(member.id) }));
      const headings = ["Member ID", "Display name", "Email address", "Membership status", "Account created", "Location", "Profession", "Industry"];
      const csv = [headings.map(csvCell).join(","), ...selectedRows.map((row) => [row.member_number, row.full_name, row.email, label(row.membership_state), row.account_created_at ? dateTime(row.account_created_at) : "", row.locality, row.profession, row.industry].map(csvCell).join(","))].join("\r\n");
      const url = URL.createObjectURL(new Blob([`\uFEFF${csv}`], { type: "text/csv;charset=utf-8" }));
      const link = document.createElement("a"); link.href = url; link.download = `one-club-member-directory-${new Date().toISOString().slice(0, 10)}.csv`; link.click(); URL.revokeObjectURL(url);
      setMessage(`${selectedRows.length} filtered member ${selectedRows.length === 1 ? "record" : "records"} exported.`);
    } catch (error) { setMessage(error instanceof Error ? error.message : "The directory could not be exported."); }
    finally { setPending(false); }
  }

  return <div className="staff-workspace member-admin-workspace-next">
    <div className="member-directory-toolbar-next">
      <label>Search members<input value={query} onChange={(event) => { setQuery(event.target.value); setPage(1); }} type="search" placeholder="Name, email or member ID" autoComplete="off" /></label>
      <label>Membership state<select value={stateFilter} onChange={(event) => { setStateFilter(event.target.value); setPage(1); }}><option value="all">All states</option><option value="active">Active</option><option value="payment_pending">Payment pending</option><option value="suspended">Suspended</option><option value="expired">Expired</option><option value="cancelled">Cancelled</option><option value="none">No membership</option></select></label>
      <label>Sort by<select value={sort} onChange={(event) => { setSort(event.target.value); setPage(1); }}><option value="name">Name A–Z</option><option value="name-desc">Name Z–A</option><option value="member-number">Member ID</option><option value="state">Membership state</option></select></label>
    </div>
    <div className="staff-toolbar member-summary-next"><p className="form-message" aria-live="polite">{message || `${filtered.length} members shown.`}</p><div><button className="button button-secondary" type="button" disabled={pending} onClick={() => { setQuery(""); setStateFilter("all"); setSort("name"); setPage(1); }}>Clear filters</button><button className="button button-secondary" type="button" disabled={pending} onClick={exportCsv}>Export CSV</button><button className="button button-secondary" type="button" disabled={pending} onClick={() => loadMembers().catch((error) => setMessage(error.message))}>Refresh</button></div></div>
    <div className="member-list-next">{visible.length ? visible.map((member) => <MemberCard key={member.id} member={member} onView={() => loadRecord(member)} onAccess={(action) => setAccessDraft({ member, action })} />) : <p className="staff-empty">No members match the selected filters.</p>}</div>
    {filtered.length > PAGE_SIZE && <nav className="member-pagination-next" aria-label="Member directory pages"><button className="button button-secondary" type="button" disabled={currentPage <= 1} onClick={() => setPage(Math.max(1, currentPage - 1))}>Previous</button><span>Page {currentPage} of {pages}</span><button className="button button-secondary" type="button" disabled={currentPage >= pages} onClick={() => setPage(Math.min(pages, currentPage + 1))}>Next</button></nav>}
    <DetailDialog open={Boolean(selected)} onClose={() => setSelected(null)}><div className="member-detail-panel-next"><button className="member-dialog-close-next" type="button" onClick={() => setSelected(null)} aria-label="Close member record">×</button><p className="eyebrow compact">MEMBER RECORD</p><h2>{record?.full_name || selected?.full_name || "Member"}</h2><p className="member-detail-email-next">{record?.email || selected?.email}</p><p className="form-message" aria-live="polite">{detailMessage}</p>{record && <MemberRecord record={record} control={control} isAdministrator={isAdministrator} pending={pending} setPending={setPending} setConfirmation={setConfirmation} refresh={refreshSelected} />}</div></DetailDialog>
    <AccessReasonDialog draft={accessDraft} onClose={() => setAccessDraft(null)} onContinue={(reason) => { if (!accessDraft) return; confirmAccess(accessDraft.member, accessDraft.action, reason); setAccessDraft(null); }} />
    <ConfirmationDialog open={Boolean(confirmation)} title={confirmation?.title || "Confirm action"} confirmLabel={confirmation?.label || "Confirm"} pending={pending} pendingLabel="Applying change…" onClose={() => !pending && setConfirmation(null)} onConfirm={runConfirmation}><p>{confirmation?.warning}</p><p>This change is recorded in the administrative audit trail.</p></ConfirmationDialog>
  </div>;
}

function MemberCard({ member, onView, onAccess }: { member: ManagedMember; onView: () => void; onAccess: (action: AccessAction) => void }) {
  const canChange = member.membership_state === "active" || member.membership_state === "suspended";
  const action: AccessAction = member.membership_state === "active" ? "suspend" : "reactivate";
  return <article className={`member-card-next member-state-${member.membership_state}`}><div><span className="staff-status">{label(member.membership_state)}</span><h2>{member.full_name || "Unnamed member"}</h2><p>{member.email}</p><small>{member.member_number || "Member ID not assigned"}</small></div><div className="member-card-actions-next"><button className="button button-secondary" type="button" onClick={onView}>View details</button>{canChange && <button className={`button ${action === "suspend" ? "member-suspend-button-next" : "button-primary"}`} type="button" onClick={() => onAccess(action)}>{action === "suspend" ? "Suspend" : "Reactivate"}</button>}</div></article>;
}

function MemberRecord({ record, control, isAdministrator, pending, setPending, setConfirmation, refresh }: { record: MemberAdminRecord; control: MembershipControl | null; isAdministrator: boolean; pending: boolean; setPending: (value: boolean) => void; setConfirmation: (value: Confirmation) => void; refresh: (message: string) => Promise<void> }) {
  async function addNote(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); const form = event.currentTarget; const note = String(new FormData(form).get("note") || "").trim(); setPending(true);
    try { const { error } = await createClient().rpc("add_member_admin_note", { p_member_id: record.id, p_note: note }); if (error) throw new Error(error.message); form.reset(); await refresh("Internal note added."); }
    catch (error) { await refresh(error instanceof Error ? error.message : "The note could not be added."); }
    finally { setPending(false); }
  }

  async function correctProfile(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); const values = new FormData(event.currentTarget); const fullName = String(values.get("full_name") || "").trim(); const phone = String(values.get("phone") || "").trim(); const reason = String(values.get("reason") || "").trim();
    setConfirmation({ title: "Save profile correction?", label: "Save correction", warning: `Update the profile record for ${record.full_name || record.email}?`, run: async () => { const { error } = await createClient().rpc("admin_update_member_profile", { p_member_id: record.id, p_full_name: fullName, p_phone: phone, p_reason: reason }); if (error) throw new Error(error.message); await refresh("Member profile corrected successfully."); } });
  }

  return <div className="member-record-content-next"><dl className="member-facts-next">{[["Member ID", record.member_number || "Not assigned"], ["Membership", label(record.membership_state)], ["Phone", record.phone || "Not provided"], ["Account created", dateTime(record.account_created_at)], ["Last sign-in", dateTime(record.last_sign_in_at)], ["Location", record.locality || "Not provided"], ["Profession", record.profession || "Not provided"], ["Industry", record.industry || "Not provided"]].map(([term, value]) => <div key={term}><dt>{term}</dt><dd>{value}</dd></div>)}</dl>
    <section className="member-metrics-next">{[["Confirmed bookings", record.bookings.confirmed], ["Pending bookings", record.bookings.pending], ["Cancelled bookings", record.bookings.cancelled], ["Successful payments", record.payments.paid], ["Pending refunds", record.refunds.pending], ["Open support requests", record.support.open]].map(([term, value]) => <div key={term}><strong>{value}</strong><span>{term}</span></div>)}</section>
    {isAdministrator && <section className="member-record-section-next"><h3>Correct member profile</h3><p>Use only to correct an identity record. The reason is audited without copying personal values into the log.</p><form className="member-form-grid-next" onSubmit={correctProfile}><label>Display name<input name="full_name" defaultValue={record.full_name || ""} minLength={2} maxLength={100} required /></label><label>Phone number<input name="phone" type="tel" defaultValue={record.phone || ""} maxLength={30} /></label><label className="wide">Mandatory reason<textarea name="reason" minLength={3} maxLength={500} required /></label><button className="button button-secondary" type="submit" disabled={pending}>Review correction</button></form></section>}
    {isAdministrator && control && <MembershipControls record={record} control={control} setConfirmation={setConfirmation} refresh={refresh} />}
    <section className="member-record-section-next"><h3>Internal notes</h3><p>Visible only to authorised staff. Notes are permanent and recorded in the audit trail.</p><form className="member-note-form-next" onSubmit={addNote}><textarea name="note" minLength={3} maxLength={1000} placeholder="Add operational context for this member" required /><button className="button button-secondary" type="submit" disabled={pending}>Add note</button></form><div className="member-notes-next">{record.notes.length ? record.notes.map((note) => <article key={note.id}><p>{note.note}</p><small>{note.author_name} · {dateTime(note.created_at)}</small></article>) : <p>No internal notes recorded.</p>}</div></section>
    <section className="member-record-section-next"><h3>Recent administrative activity</h3><div className="member-actions-list-next">{record.recent_actions.length ? record.recent_actions.map((action, index) => <article key={`${action.created_at}-${index}`}><strong>{label(action.action)}</strong><small>{dateTime(action.created_at)}</small></article>) : <p>No administrative activity recorded for this member.</p>}</div></section>
  </div>;
}

function MembershipControls({ record, control, setConfirmation, refresh }: { record: MemberAdminRecord; control: MembershipControl; setConfirmation: (value: Confirmation) => void; refresh: (message: string) => Promise<void> }) {
  const [action, setAction] = useState<MembershipAction>(() => availableActions(control)[0]?.value || "cancel");
  const options = availableActions(control);
  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault(); const values = new FormData(event.currentTarget); const reason = String(values.get("reason") || "").trim(); const plan = String(values.get("plan") || "annual") as "founding_lifetime" | "annual"; const actionLabel = options.find((option) => option.value === action)?.label || "Apply membership change";
    setConfirmation({ title: `${actionLabel}?`, label: actionLabel, warning: `Apply “${actionLabel}” to ${record.full_name || record.email}?`, run: async () => {
      const supabase = createClient(); let error: { message: string } | null = null;
      if (action === "cancel") ({ error } = await supabase.rpc("admin_cancel_membership", { p_member_id: record.id, p_reason: reason }));
      if (action === "revoke_offer") ({ error } = await supabase.rpc("admin_revoke_pending_membership_offer", { p_member_id: record.id, p_reason: reason }));
      if (action === "expiry") ({ error } = await supabase.rpc("admin_change_membership_expiry", { p_member_id: record.id, p_new_expiry: new Date(String(values.get("new_expiry"))).toISOString(), p_reason: reason }));
      if (action === "complimentary") ({ error } = await supabase.rpc("admin_grant_complimentary_membership", { p_member_id: record.id, p_plan: plan, p_reason: reason }));
      if (action === "restore_cancelled_offer") ({ error } = await supabase.rpc("admin_restore_cancelled_membership_offer", { p_member_id: record.id, p_reason: reason }));
      if (action === "restore_expired_complimentary") ({ error } = await supabase.rpc("admin_restore_expired_membership_complimentary", { p_member_id: record.id, p_reason: reason }));
      if (action === "reopen_expired_payment") ({ error } = await supabase.rpc("admin_reopen_expired_membership_for_payment", { p_member_id: record.id, p_reason: reason }));
      if (action === "offline") ({ error } = await supabase.rpc("admin_record_offline_membership_payment", { p_member_id: record.id, p_plan: plan, p_amount_paise: Math.round(Number(values.get("amount_rupees")) * 100), p_payment_method: String(values.get("payment_method")), p_transaction_reference: String(values.get("transaction_reference") || ""), p_payment_received_at: new Date(String(values.get("payment_received_at"))).toISOString(), p_reason: reason }));
      if (error) throw new Error(error.message); await refresh("Membership change applied successfully.");
    } });
  }
  const requiresPlan = action === "complimentary" || action === "offline"; const offline = action === "offline";
  return <section className="member-record-section-next"><h3>Membership controls</h3><p>{control.plan === "founding_lifetime" ? `Founding Member #${control.founding_sequence} · Lifetime membership` : `${control.plan ? label(control.plan) : "No configured plan"}${control.expires_at ? ` · Valid until ${dateTime(control.expires_at)}` : ""}${control.payment_offer_expires_at ? ` · Payment offer closes ${dateTime(control.payment_offer_expires_at)}` : ""}`}</p>{options.length ? <form className="member-form-grid-next" onSubmit={submit}><label className="wide">Administrative action<select name="action" value={action} onChange={(event) => setAction(event.target.value as MembershipAction)}>{options.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}</select></label>{requiresPlan && <label>Membership plan<select name="plan" defaultValue={control.founding_sequence ? "founding_lifetime" : "annual"}><option value="founding_lifetime" disabled={!control.founding_sequence && control.founding_places_remaining <= 0}>Founding Member · Lifetime</option><option value="annual">Member · 12 months</option></select></label>}{action === "expiry" && <label>New expiry date<input name="new_expiry" type="datetime-local" defaultValue={localInputDate(control.expires_at)} required /></label>}{offline && <><label>Amount received (₹)<input name="amount_rupees" type="number" min="1" step="1" required /></label><label>Payment method<select name="payment_method"><option value="bank_transfer">Bank transfer</option><option value="upi">UPI</option><option value="card_pos">Card / POS</option><option value="cash">Cash</option><option value="cheque">Cheque</option><option value="other">Other</option></select></label><label>Transaction reference<input name="transaction_reference" maxLength={120} /></label><label>Payment received<input name="payment_received_at" type="datetime-local" defaultValue={localInputDate()} required /></label></>}<label className="wide">Mandatory reason<textarea name="reason" minLength={3} maxLength={500} required /></label><label className="wide member-confirm-next"><input type="checkbox" required /><span>I verified this member and understand that this action is recorded in the audit log.</span></label><button className="button button-primary" type="submit">Review and apply</button></form> : <p>No membership actions are currently available for this account.</p>}<div className="membership-terms-next">{control.terms.map((term) => <article key={term.id}><strong>{label(term.plan)} · {label(term.status)}</strong><p>{term.expires_at ? `${dateTime(term.starts_at)} — ${dateTime(term.expires_at)}` : `From ${dateTime(term.starts_at)} · Lifetime`}</p><small>{label(term.source)}{term.transaction_reference ? ` · ${term.transaction_reference}` : ""}</small></article>)}</div></section>;
}

function availableActions(control: MembershipControl): { value: MembershipAction; label: string }[] {
  const options: { value: MembershipAction; label: string }[] = [];
  if (["active", "suspended"].includes(control.membership_state)) options.push({ value: "cancel", label: "Cancel membership" });
  if (control.membership_state === "payment_pending") options.push({ value: "revoke_offer", label: "Revoke pending membership offer" }, { value: "complimentary", label: "Grant complimentary membership" }, { value: "offline", label: "Record offline membership payment" });
  if (control.plan === "annual" && ["active", "suspended"].includes(control.membership_state)) options.push({ value: "expiry", label: "Change expiry date" });
  if (control.membership_state === "cancelled") options.push({ value: "restore_cancelled_offer", label: "Restore membership offer" });
  if (control.membership_state === "expired") options.push({ value: "restore_expired_complimentary", label: "Restore as complimentary" }, { value: "reopen_expired_payment", label: "Reopen for payment" });
  const renewalDay = control.plan === "annual" && control.expires_at && new Date().toDateString() === new Date(control.expires_at).toDateString();
  if (renewalDay) options.push({ value: "offline", label: "Record offline renewal payment" });
  return options;
}
