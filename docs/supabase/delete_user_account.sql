-- §15A — Supabase RPC for self-service account deletion.
--
-- App Store Guideline 5.1.1(v) requires apps that support
-- account creation to also support in-app account deletion.
-- Trakrr's current Settings → Delete Account flow opens a
-- mailto: to support, which technically satisfies the guideline
-- but requires manual processing. This RPC moves it to a
-- one-tap in-app path that completes within seconds.
--
-- The function is SECURITY DEFINER so it can DELETE FROM
-- auth.users (which RLS would otherwise block). It pulls the
-- caller's user_id from auth.uid() rather than taking it as
-- a parameter — this prevents one authenticated user from
-- deleting another. Anonymous callers (auth.uid() IS NULL)
-- are rejected.
--
-- Deletion order matters because of foreign-key dependencies.
-- We walk from leaf tables to root: child rows first, then
-- the profile, then the auth row. Each DELETE is wrapped in
-- the same transaction so a failure mid-way rolls back
-- everything — partial deletion would leave the user in a
-- broken state ("can't sign in but follows still exist").
--
-- Future-extensibility note: any new table that references
-- a user MUST be added to this cascade or the auth.users
-- delete will fail with a foreign-key violation. The
-- comment block below lists the current tables; keep it in
-- sync as the schema grows.
--
-- DEPLOY:
--   1. Supabase Dashboard → SQL Editor → New query.
--   2. Paste this whole file.
--   3. Run. The function is created in the `public` schema.
--   4. Verify with:
--      SELECT proname FROM pg_proc WHERE proname = 'delete_user_account';
--   5. Test from the app side: AuthService.shared.deleteAccount().
--      First test should be against a throwaway account.
--
-- ROLLBACK:
--   DROP FUNCTION public.delete_user_account();

CREATE OR REPLACE FUNCTION public.delete_user_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
    me uuid := auth.uid();
BEGIN
    -- Reject anonymous calls. SECURITY DEFINER functions run
    -- as the function owner (postgres), so without this guard
    -- a public.delete_user_account() call from an unauthed
    -- client would silently succeed and delete... nothing
    -- (auth.uid() is null), but the principle stands: only
    -- authenticated users may invoke this.
    IF me IS NULL THEN
        RAISE EXCEPTION 'delete_user_account requires an authenticated caller';
    END IF;

    -- 1. follows — both directions. The athlete's follows OUT
    --    + everyone who follows them.
    DELETE FROM public.follows
    WHERE follower_user_id = me OR followed_user_id = me;

    -- 2. duo_races — either side. Currently identified by
    --    host_user_id / guest_user_id columns (cloud Duo Tier 2
    --    rows; Multipeer-only duo races aren't in Postgres).
    DELETE FROM public.duo_races
    WHERE host_user_id = me OR guest_user_id = me;

    -- 3. races — every race row owned by this user. The
    --    user_id column is the FK to auth.users.
    DELETE FROM public.races
    WHERE user_id = me;

    -- 4. race-photos storage objects. The bucket layout is
    --    `<user_id>/<race_id>.jpg` so we can target the
    --    user's prefix directly. storage.objects exposes
    --    `name` (the full path) so we LIKE-match the prefix.
    DELETE FROM storage.objects
    WHERE bucket_id = 'race-photos'
      AND name LIKE me::text || '/%';

    -- 5. avatars storage objects, same shape. Bucket name
    --    may differ in production — adjust the bucket_id
    --    string if it's not literally 'avatars'.
    DELETE FROM storage.objects
    WHERE bucket_id = 'avatars'
      AND name LIKE me::text || '/%';

    -- 6. profile — the public-facing row keyed by `id`
    --    matching auth.uid().
    DELETE FROM public.profiles
    WHERE id = me;

    -- 7. auth.users — last because it cascades elsewhere
    --    we may not have covered. Supabase's auth schema
    --    handles its own internal cascades (sessions,
    --    refresh tokens, identities).
    DELETE FROM auth.users
    WHERE id = me;
END;
$$;

-- Grant invoke to authenticated role only. Anonymous callers
-- get rejected by the auth.uid() guard above, but locking
-- the grant down too is defense in depth.
REVOKE ALL ON FUNCTION public.delete_user_account() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_user_account() FROM anon;
GRANT EXECUTE ON FUNCTION public.delete_user_account() TO authenticated;

COMMENT ON FUNCTION public.delete_user_account() IS
'§15A — Self-service account deletion. Cascades through follows, duo_races, races, race-photos + avatars storage, profiles, and auth.users. SECURITY DEFINER so it can reach auth.users; gated on auth.uid() so users can only delete themselves.';
