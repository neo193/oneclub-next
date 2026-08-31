# Supabase deployment assets

This directory is the versioned copy of the database migrations and Edge Functions used by the One Club application. The migration history begins after the original prototype schema was created in the hosted Supabase project, so it must not yet be treated as a complete empty-database bootstrap.

Before a clean staging or production launch, capture the baseline definitions for the tables and older RPCs that predate migration `20260823_001`, particularly:

- `get_active_member_benefits()`
- `cancel_event_booking(uuid)`
- `submit_member_support_request(text, text)`
- membership invitation validation and acceptance

Do not recreate these functions from assumptions. Export their definitions from the hosted project, review their security-definer checks and grants, and add them as an earlier baseline migration. Later migrations and `functions/razorpay-payments` are now versioned here.

Generate application types from the linked Supabase project whenever the schema changes:

```sh
supabase gen types typescript --linked > src/types/database.generated.ts
```

The generated file should be reviewed alongside migrations and never contain credentials.
