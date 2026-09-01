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

## Cloudflare development deployment

This is a full-stack application and must be deployed to Cloudflare Workers, not
as a static Cloudflare Pages export. The repository includes the vinext adapter,
`vite.config.ts`, and `wrangler.jsonc`.

Cloudflare Workers Builds configuration:

- Repository: `neo193/oneclub-next`
- Production branch: `main`
- Build command: `npm run build:vinext`
- Deploy command: `npm run deploy:vinext`
- Worker name: `oneclub-next-dev`

Required build variables:

- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY`
- `NEXT_PUBLIC_LEGACY_SITE_URL=https://dev.oneclub.net.in`

Test the generated `workers.dev` deployment before moving the custom domain.
Then remove `dev.oneclub.net.in` from the legacy Pages project and add it as a
custom domain on the `oneclub-next-dev` Worker. Keep the old Pages project intact
until the new deployment has passed authentication and role-based smoke tests.

