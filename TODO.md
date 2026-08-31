# One Club Next.js roadmap

## Framework migration

- [x] Migrate the shared public shell and public content pages.
- [x] Migrate authentication, password recovery and invite flows.
- Migrate the member portal and member-only pages.
- Migrate staff and administrator workspaces.
- Generate strict database types from the Supabase project before migrating data-heavy pages.
- Complete route-level authorization and production deployment configuration.

## Partner reservations

Stages 1 and 2 are complete in the legacy application. Migrate and regression-test
those workflows before continuing with the stages below.

### Stage 3: walk-in membership verification

- Add a short-lived, single-use QR verification challenge to the member portal.
- Provide a public partner scanning page without requiring partner accounts.
- Send an OTP to the member's registered WhatsApp number after a valid scan.
- Require the property staff to enter the OTP before confirming membership access.
- Protect against screenshots, replay attempts, OTP guessing and excessive requests.
- Show the property only the member name, membership validity and applicable benefit.

### Stage 4: visit and benefit-redemption records

- Convert successful walk-in verification into a property visit/redemption record.
- Store the partner, property, member, source, benefit, party size and verification result.
- Give staff operational history and members an appropriate visit history.
- Prevent accidental duplicate redemptions while permitting legitimate repeat visits.

### Stage 5: production hardening

- Connect reservation notifications to production email delivery.
- Connect WhatsApp notifications after the business account is available.
- Add retries, idempotency, rate limits, failure visibility and staff escalation.
- Preserve an immutable audit trail for reservations, cancellations, verification and redemption.
- Add operational reporting and confirm data-retention and privacy rules.

## Launch readiness

- Add the existing membership-invitation validation and acceptance RPCs to the versioned migration history.
- Convert prototype database changes into repeatable, versioned migrations.
- Separate demonstration data from production-ready records.
- Rehearse backup, restore, rollback and clean-staging deployment procedures.
- Prepare production secrets and service configuration without committing credentials.
- Validate authentication redirects, payments, webhooks, scheduled jobs, security and monitoring.
