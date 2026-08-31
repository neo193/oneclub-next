<!-- BEGIN:nextjs-agent-rules -->

# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` (resolved from this file's directory; in monorepos the `next` package may not be visible from the repo root) before writing any code. Heed deprecation notices.

This block is written and re-added by `next dev` — verify at `node_modules/next/dist/server/lib/generate-agent-files.js`. Removing it from a diff only re-creates the uncommitted change; committing it with your work keeps the tree clean.

<!-- END:nextjs-agent-rules -->

# One Club persistent agent instructions

## Product and migration boundaries

- This repository is the Next.js successor to the legacy static One Club application. Migrate one workflow at a time and preserve the established black, cream and gold visual system.
- The current stack is Next.js 16 App Router, React 19, TypeScript and Supabase. Do not introduce another UI framework or state-management library without an explicit product need.
- Partner reservations are deliberately deferred. Do not add reservation navigation or a reservation workspace to the staff portal until the user resumes that module.
- Existing Supabase data and migrations are authoritative. Never reset, truncate or destructively recreate the hosted database. Add forward-only, idempotent migrations when schema work is required.
- Never commit `.env.local`, API tokens, Supabase service-role keys, Razorpay secrets or Cloudflare credentials. Browser code may only use `NEXT_PUBLIC_*` values intended for public exposure.

## Required working method

- Read `AI_HANDOFF.md` and `TODO.md` before implementation. Keep both accurate when a migration stage materially changes.
- Before changing Next.js behavior, read the relevant documentation under `node_modules/next/dist/docs/` as required by the generated rule above.
- Reuse the shared shells, buttons, confirmation dialog and CSS design tokens. Avoid page-specific copies of reusable UI; global overlays such as dialogs must live in `src/app/globals.css`.
- Maintain server-side authorization in addition to navigation visibility. Hiding a link is not access control.
- Keep privileged provider calls server-side. Technical diagnostics must never return secrets, raw security logs, visitor IPs or unnecessary member data.
- Destructive financial actions require an explicit confirmation dialog, idempotent backend behavior and clear success/error feedback.
- Preserve unrelated user changes in the working tree. Do not use destructive Git commands.

## Quality and handoff gates

- Before presenting a stage as complete, run `npm run typecheck`, `npm run lint`, `git diff --check` and `npm run build` (or `node node_modules/next/dist/bin/next build --webpack` if the default builder is unsuitable locally).
- The production build may rewrite `next-env.d.ts` from `.next/dev/types` to `.next/types`. Restore the committed development form after validation if that is the only generated diff.
- Test responsive layouts at approximately 440px width as well as desktop. The member portal previously suffered from fixed-width overflow.
- Do not claim live Razorpay refunds, emails, Cloudflare metrics or hosted database mutations were tested unless they were actually exercised with configured credentials.
- When finishing a stage, state what was implemented, what was validated automatically, what still requires authenticated browser testing and what remains intentionally deferred.

