# One Club Next.js migration

This application is the typed, component-based successor to the existing static
One Club website. The legacy pages remain untouched while routes are migrated and
verified one workflow at a time.

## Local setup

1. Copy `.env.example` to `.env.local` and add the existing public Supabase values.
2. Run `npm install`.
3. Run `npm run dev`.

Quality gates:

- `npm run typecheck`
- `npm run lint`
- `npm run build`

## Migration order

1. Shared public shell and public content pages.
2. Authentication and recovery flows.
3. Member portal and member-only pages.
4. Staff and admin workspaces.
5. Partner reservations and remaining operational workflows.

Database types in `src/types/database.ts` are an explicit placeholder. Generate
them from the Supabase project before migrating data-heavy pages.

