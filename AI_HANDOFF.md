# One Club Next.js — AI handoff

Last updated: 31 August 2026

## Objective

This repository (`oneclub-next`) is replacing the original HTML/CSS/JavaScript One Club website with a typed, component-based Next.js application. The legacy site remains the functional reference while workflows are migrated and verified incrementally. Cloudflare can later be pointed at this repository once migration and production readiness are complete.

## Current architecture

- Next.js 16.3.3 App Router, React 19.2 and TypeScript 5.9.
- Supabase authentication, database RPCs and row-level security.
- Razorpay operations are delegated to the versioned `supabase/functions/razorpay-payments` Edge Function.
- Public, authentication, member and staff route groups live under `src/app`.
- Shared Supabase clients are in `src/lib/supabase`; role/profile logic is in `src/lib/auth`.
- Shared visual tokens and public styles are in `src/app/globals.css`. Member and staff responsive styles are scoped in their route-group CSS files.
- Explicit database contracts currently live in `src/types/database.ts`. A full generated Supabase type export is still desirable once a linked CLI session is available.

## Completed work

### Public website

- Shared responsive header, navigation, footer and public shell.
- Home, About, Membership, Benefits, Partners, Events, Contact, Privacy and Terms pages.
- Reusable public cards and consistent card styling.
- Enquiry form and responsive public presentation.

### Authentication

- Login, callback, logout, forgot/reset password and membership invitation routes.
- Login uses a server action so Supabase session cookies are established before protected redirects.
- Role-aware redirecting to member, staff or administrator destinations.
- Login fields remain initially blank while browser autofill suggestions remain available after interaction.

### Member portal

- Responsive member shell and mobile navigation.
- Portal home and membership card.
- Benefits catalogue.
- Events booking lifecycle, guest selection, Razorpay payment handling, pending/confirmed/cancelled bookings and cancellation confirmation.
- Profile editor and member support form.
- Membership payment UI.
- Mobile layouts were corrected across all member-facing routes, including booking-action alignment.

### Staff and administrator portal

- Shared role-aware staff shell, navigation and server-side workspace guards.
- Staff landing workspace.
- Administrator overview.
- Invitation and enquiry approval workspace.
- Support operations workspace.
- Administrator refund operations:
  - Pending and processed refund queue.
  - Razorpay reconciliation.
  - Full-refund issuing through the payment Edge Function.
  - Shared irreversible-action confirmation modal, centered on desktop and mobile.
- Technical diagnostics:
  - Application, Supabase database/authentication, payment and data-integrity checks.
  - Optional Cloudflare Pages deployment and security metrics.
  - Server-only provider credentials and sanitized browser responses.
- Member administration:
  - Searchable, filterable and paginated member directory with filtered CSV export.
  - Responsive member record containing account facts, booking/payment/refund/support metrics, internal notes and audit activity.
  - General staff and administrator suspend/reactivate controls with mandatory reasons and immediate UI refresh.
  - Administrator-only profile corrections, membership cancellation/offer restoration, complimentary activation, expiry changes and offline payment recording.
  - Shared confirmation workflow for audited or destructive actions.
- Event management:
  - Marketing staff and administrator event catalogue workspace with create/edit/status controls.
  - Capacity, booking window, refund cutoff, guest-limit and per-person/fixed-booking price configuration.
  - Published-event capacity-change reasons and backend committed-seat safeguards.
  - Deletion eligibility checks and irreversible-action confirmation; events with booking history must be cancelled instead.
  - Administrator-only complimentary bookings for active members, including guest limits, capacity checks and audited reasons.

## Authorization model

- Administrators can access every currently migrated staff workspace.
- General staff can access invitations, member administration, support and partner management when those routes exist.
- Marketing staff can access invitations and event management when migrated.
- Technical staff can access invitations and diagnostics.
- Refunds and administrator overview are administrator-only.
- Navigation filtering is defined in `src/lib/staff/navigation.ts`; actual route authorization is enforced through `src/lib/staff/access.ts` and authenticated profile helpers. Preserve both layers.

## Database and backend state

- Versioned migration history is under `supabase/migrations` and currently runs from enquiries/auth through member, event, refund, partner-property and legacy reservation schema changes.
- The Razorpay payment Edge Function source is under `supabase/functions/razorpay-payments/index.ts`.
- Some baseline RPCs predate the imported migration history. Read `supabase/README.md` before assuming a clean database can be reconstructed entirely from the checked-in files.
- The user previously ran the required SQL for earlier reservation work in the hosted project. Do not rerun migrations blindly or reset the database.

## Environment and local development

Copy `.env.example` to `.env.local` and supply:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_LEGACY_SITE_URL`

Optional server-only diagnostics configuration:

- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_WORKER_NAME` (currently `oneclub-next`)
- `CLOUDFLARE_ZONE_ID`

Without Cloudflare variables, diagnostics intentionally reports those provider checks as not configured while core checks continue to work. Never expose these values through `NEXT_PUBLIC_*` variables.

Local commands:

```text
npm install
npm run dev
npm run typecheck
npm run lint
npm run build
```

The development URL is normally `http://localhost:3000`.

### Current Codex runtime caveat

In the present desktop runtime, the global `npm` command may fail because its shim points to a removed `%APPDATA%\npm\node_modules\npm\bin\npm-cli.js`. This is a host PATH/shim issue, not a project issue. The installed project tools work directly:

```text
.\node_modules\.bin\tsc.cmd --noEmit
.\node_modules\.bin\eslint.cmd .
node node_modules/next/dist/bin/next dev
node node_modules/next/dist/bin/next build --webpack
```

Use those commands when necessary; do not modify application code to compensate for the global npm shim.

## Required manual regression tests

- Authenticate as a member, general staff, marketing staff, technical staff and administrator where test accounts are available.
- Confirm each role sees only its allowed staff navigation and receives a redirect from forbidden routes.
- Member: test benefit display, profile update, support request and event booking states on desktop and a roughly 440px mobile viewport.
- Refund administrator: load queue, cancel the confirmation dialog without mutation, reconcile a refund, and only issue a real refund when using an intentionally refundable test payment.
- Diagnostics: run core checks as administrator and technical staff; confirm other roles cannot use the API or page.
- Do not treat an automated build as proof that emails, Razorpay, Cloudflare or hosted Supabase side effects succeeded.

## Next work

Continue the staff/admin migration without reservations:

1. Finish staff-stage regression testing and production deployment configuration. Partner, benefit and property management is now migrated at `/staff/partners`, with one benefit per partner, primary and additional location editing, reservation contact metadata, and guarded deletion.
2. Full role/access and responsive regression pass.
3. Production deployment configuration and complete generated Supabase types.

Only after the framework migration is stable should the legacy partner reservation module be migrated and its later stages resumed. The planned reservation stages are retained in `TODO.md`.

## Important known constraints

- Partner reservations must remain absent from current staff navigation and workspaces.
- The single-benefit business rule is one benefit package per partner; reservation property eligibility depends on reservation email and phone, not on a separate benefit-presence check.
- WhatsApp integration is intentionally deferred until a business number/account exists. Future notification design must keep the provider replaceable and server-side.
- Cloudflare deployment/security diagnostics require a suitably scoped token and should degrade safely when missing.
- Never place financial secrets, service-role credentials or provider tokens in client components.

## Current validation state

Immediately before this handoff, TypeScript, ESLint, `git diff --check` and a production Next.js webpack build passed. The unauthenticated technical-diagnostics API returned HTTP 401 as expected. Authenticated browser verification remains necessary for live refund/provider behavior.
