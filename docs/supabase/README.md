# Supabase Schema + RPC Migrations

SQL migrations for Trakrr's cloud-backed features. Run these
through the Supabase Dashboard → SQL Editor, in the order listed
below.

## Files

| Order | File | Purpose | Required for |
| --- | --- | --- | --- |
| 1 | `profiles_bootstrap.sql` | `profiles` table + RLS + `updated_at` trigger + `public_profiles` view (security_invoker=false) + auth.users → profiles backfill. Documents what was originally created out-of-band so a fresh project / restored snapshot can rebuild from this repo alone. | v1 auth + sync, cross-user search, follow flows, public profile cards |
| 2 | `duo_races.sql` | Coordination table for cross-city HYROX Doubles. Schema + indexes + RLS policies + updated_at trigger. | §4.5 Tier 2 Cloud Duo Mode |
| 3 | `delete_user_account.sql` | Self-service account deletion RPC. Cascades through follows, duo_races, races, race-photos + avatars storage, profiles, and auth.users. SECURITY DEFINER, gated on auth.uid(). | §15A App Store Guideline 5.1.1(v) compliance |

## Deploy

For each file:

1. Open it in your editor (`docs/supabase/<file>.sql`)
2. Select all → copy
3. Supabase Dashboard → SQL Editor → New query → paste
4. Click **Run** (or ⌘↵)
5. Verify the expected output (each file's header comment lists
   what to run to verify)

## Realtime

Some tables require **Realtime** to be enabled separately:

- `follows` — used by `FollowSyncService` for live follower /
  following count + list updates (§16)
- `duo_races` — used by `CloudDuoSession` for hosting + claim
  flow visibility (§4.5 Tier 2)

To enable Realtime on a table:

1. Supabase Dashboard → Database → Publications
2. Click `supabase_realtime`
3. Check the box next to each table that needs Realtime
4. Save

## After deploying

- The iOS app picks up the schema changes on the next launch.
  No client-side migration is needed; all Codable DTOs use
  `decodeIfPresent` so new columns are forward-compat.
- If you re-run `duo_races.sql` after edits, it's idempotent —
  `CREATE TABLE IF NOT EXISTS`, `DROP POLICY IF EXISTS` before
  each `CREATE POLICY`, etc.
- Test the delete-account flow on a throwaway account before
  flipping it on for production users.

## Adding a new migration

1. Drop the SQL file into this folder following the existing
   header-comment convention (purpose, deploy steps, rollback).
2. Add a row to the table above.
3. Commit + push.
4. Deploy via the steps in §Deploy.

There's no automated migration runner today — every change is
manual through the Dashboard. When the schema gets complex
enough that this becomes painful, migrate to Supabase CLI
(`supabase migration new`) which gives us versioned migrations
+ a CI deploy story.
