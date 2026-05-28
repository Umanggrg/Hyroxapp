-- Profiles table bootstrap + public_profiles view.
--
-- The `profiles` table was created out-of-band in the Supabase
-- Dashboard during early v1 sync work and was never captured
-- here. This file documents the canonical shape so future
-- deploys (a fresh project, a restored snapshot, a new dev
-- environment) can be reproduced from the repo alone.
--
-- Phase 60: a real production bug surfaced that all three
-- TestFlight test accounts ended up with no `profiles` row —
-- `ProfileSyncService.syncOnSignIn` upsert was failing
-- silently and the bare `try?` discarded the error. Search,
-- public profile cards, and follow flows all break when this
-- happens. The Swift side is patched to log + assert on push
-- failure; this SQL is the deploy-side belt-and-braces.
--
-- DEPLOY
--   1. Supabase Dashboard → SQL Editor → New query
--   2. Paste this file → Run
--   3. Verify with the probes at the bottom of the file
--
-- ROLLBACK
--   DROP VIEW IF EXISTS public.public_profiles;
--   DROP TABLE IF EXISTS public.profiles CASCADE;

-- ============================================================
-- 1. Table
-- ============================================================
--
-- Per-user profile. id is the auth.users.id (uuid) — RLS gates
-- everything to "you can only touch your own row". Cross-user
-- discovery happens through the `public_profiles` view below,
-- which intentionally bypasses RLS via security_invoker=false.
--
-- Fields match `RemoteProfileWrite` in
-- `Hyroxapp/Shared/RemoteProfile.swift`. When adding columns:
-- add them as NULLABLE first, fill them with a backfill, then
-- consider a NOT NULL constraint. NEVER add a non-nullable
-- column without a default — pre-existing rows will fail the
-- migration.

CREATE TABLE IF NOT EXISTS public.profiles (
    id              uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Display name shown in the profile header. Free text.
    -- Not normalized. Can be blank during a freshly-backfilled
    -- account that hasn't completed onboarding.
    display_name    text NOT NULL DEFAULT '',

    -- The athlete's @handle. Lowercased, alphanumeric +
    -- underscore. Globally unique once onboarding completes.
    -- A backfilled placeholder (derived from email prefix) may
    -- collide if two accounts had similar emails; resolve by
    -- editing in the Profile tab.
    handle          text NOT NULL DEFAULT '',

    location        text NOT NULL DEFAULT '',
    bio             text NOT NULL DEFAULT '',

    -- HYROX division as the snake_case raw value of the
    -- `Division` enum in iOS. Allowed: mens_open, womens_open,
    -- mens_pro, womens_pro.
    division        text NOT NULL DEFAULT 'mens_open',

    -- Used by HR zone calculations. 190 is the iOS app's
    -- default until the athlete sets a custom max.
    max_heart_rate  integer NOT NULL DEFAULT 190,

    -- URL into the `avatars` Supabase Storage bucket. Nullable
    -- because most users haven't uploaded one. Set via
    -- PhotoStorageService.uploadAvatar.
    avatar_url      text,

    created_at      timestamptz NOT NULL DEFAULT now(),
    updated_at      timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. updated_at trigger
-- ============================================================

CREATE OR REPLACE FUNCTION public.profiles_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_updated_at ON public.profiles;
CREATE TRIGGER profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.profiles_set_updated_at();

-- ============================================================
-- 3. RLS policies
-- ============================================================
--
-- The shape is "you can only touch your own row." Cross-user
-- reads happen ONLY through the `public_profiles` view below,
-- which projects the safe-to-expose columns and bypasses RLS
-- so search can find other athletes.
--
-- Idempotent — DROP before each CREATE so re-running is safe.

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
DROP POLICY IF EXISTS profiles_insert_own ON public.profiles;
DROP POLICY IF EXISTS profiles_update_own ON public.profiles;

CREATE POLICY profiles_select_own ON public.profiles
    FOR SELECT
    TO authenticated
    USING (auth.uid() = id);

CREATE POLICY profiles_insert_own ON public.profiles
    FOR INSERT
    TO authenticated
    WITH CHECK (auth.uid() = id);

CREATE POLICY profiles_update_own ON public.profiles
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = id)
    WITH CHECK (auth.uid() = id);

-- ============================================================
-- 4. public_profiles view (cross-user discovery)
-- ============================================================
--
-- Read-only projection of `profiles` exposing the columns that
-- are safe for any authenticated user to see: identity (id,
-- handle, display_name), public-facing chrome (avatar, bio,
-- location, division), and recency (created_at). NOT exposed:
-- max_heart_rate, updated_at — those are personal training
-- data and persistence chrome respectively.
--
-- `WITH (security_invoker = false)` is critical — the view
-- runs as the view owner (postgres), which bypasses the
-- `profiles_select_own` RLS policy. Without this, every
-- authenticated user would only ever see their own row in
-- the view (the same restriction the underlying table has),
-- and cross-user search would always return zero matches.
--
-- This is the canonical Supabase pattern for "private table +
-- public view": store the private superset in a row-locked
-- table, expose the public subset through a security-definer
-- view, grant SELECT on the view to authenticated/anon.

DROP VIEW IF EXISTS public.public_profiles;

CREATE VIEW public.public_profiles
  WITH (security_invoker = false) AS
  SELECT id, display_name, handle, location, bio, division, avatar_url, created_at
    FROM public.profiles;

GRANT SELECT ON public.public_profiles TO authenticated, anon;

-- ============================================================
-- 5. Backfill — seed profiles for auth.users that lack one
-- ============================================================
--
-- Idempotent: skips users that already have a row. Inserts a
-- placeholder profile derived from the email prefix:
--   handle       = lowercased alphanumeric of email local-part
--   display_name = email local-part verbatim
--   division     = mens_open (athlete edits in onboarding)
--   max_heart_rate = 190 (iOS default)
--
-- Re-running this after onboarding completes will NOT clobber
-- the user's edits — the NOT EXISTS guard skips populated
-- rows.

INSERT INTO public.profiles
    (id, handle, display_name, location, bio, division, max_heart_rate, avatar_url)
SELECT
    u.id,
    LOWER(REGEXP_REPLACE(SPLIT_PART(u.email, '@', 1), '[^a-z0-9_]', '', 'g')),
    SPLIT_PART(u.email, '@', 1),
    '',
    '',
    'mens_open',
    190,
    NULL
  FROM auth.users u
 WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);

-- ============================================================
-- 6. Verification probes
-- ============================================================
--
-- A. Confirm every auth.users row has a profiles row.
--    Expected: 0 rows (every user has a profile).
--
-- SELECT u.id, u.email
--   FROM auth.users u
--  WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id);
--
-- B. Confirm cross-user reads succeed through the view.
--    Run as an authenticated user (NOT as the postgres role —
--    the dashboard SQL Editor runs as postgres by default,
--    which bypasses RLS regardless. Use the API logs to see
--    real authenticated-role queries from the iOS app).
--    Expected: at least one row, ideally many.
--
-- SELECT id, handle, display_name FROM public.public_profiles LIMIT 5;
--
-- C. Confirm the view is set to security_invoker = false.
--    Expected: one row with reloptions containing
--    'security_invoker=false'.
--
-- SELECT relname, reloptions
--   FROM pg_class
--  WHERE relname = 'public_profiles' AND relkind = 'v';
