-- §4.5 Tier 2 — Cloud-backed Duo Mode schema.
--
-- Coordination table for cross-city HYROX Doubles. Two athletes
-- in different gyms pair via a 6-character code, claim a room
-- row, then exchange race-time events over Supabase Realtime
-- broadcast (the row itself stays as room metadata only; race
-- events don't write Postgres on every advance).
--
-- The Swift side (CloudDuoSession + CloudDuoCoordinator) reads
-- and writes this table via the supabase-swift client. RemoteDuoRace
-- in `Hyroxapp/Shared/DuoSync/RemoteDuoRace.swift` is the wire DTO;
-- keep its column names + types in sync with this schema.
--
-- ROW LIFECYCLE
--   1. Host INSERT (CloudDuoSession.startHosting)
--      → status='waiting', host_user_id=self, guest_user_id=null,
--        pair_code=DuoRoomCode.random()
--   2. Guest SELECT by pair_code + 'waiting' (CloudDuoSession.joinRoom step 1)
--   3. Guest UPDATE claim (CloudDuoSession.joinRoom step 2)
--      → status='paired', guest_user_id=self
--   4. Host UPDATE on race start
--      → status='racing', started_at=now()
--   5. Either side UPDATE on race finish
--      → status='finished', ended_at=now()
--   6. Cancel path: UPDATE status='abandoned' (or just leave it)
--
-- DEPLOY
--   1. Supabase Dashboard → SQL Editor → New query
--   2. Paste this file → Run
--   3. Verify the table exists:
--      SELECT relname FROM pg_class WHERE relname = 'duo_races';
--   4. Verify Realtime is enabled (Database → Publications →
--      supabase_realtime → check the duo_races box).
--
-- ROLLBACK
--   DROP TABLE public.duo_races CASCADE;

-- ============================================================
-- 1. Table
-- ============================================================

CREATE TABLE IF NOT EXISTS public.duo_races (
    id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 6-character pair code. Generated client-side by
    -- DuoRoomCode.random() so the host can display it
    -- immediately without a network round-trip. Charset is
    -- intentionally restricted (no 0/O/1/I) for readability.
    -- See DuoRoomCode.swift for the exact alphabet.
    pair_code     text NOT NULL,

    -- Host = the athlete who tapped "Host" first. Their UUID
    -- is set on INSERT. ON DELETE CASCADE so when a user
    -- deletes their account, their duo rows go too — paired
    -- with the delete_user_account RPC's cleanup.
    host_user_id  uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

    -- Guest = the joiner. Null in the waiting state; populated
    -- by the UPDATE in CloudDuoSession.joinRoom.
    guest_user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,

    -- State machine:
    --   'waiting'   — host created, no guest yet
    --   'paired'    — guest claimed, ready to race
    --   'racing'    — race in progress
    --   'finished'  — race completed cleanly
    --   'abandoned' — pairing cancelled before race start
    status        text NOT NULL DEFAULT 'waiting'
        CHECK (status IN ('waiting', 'paired', 'racing', 'finished', 'abandoned')),

    -- Server timestamp of race start. Set when the host taps
    -- Start on the race screen. Used to give both clients an
    -- authoritative timer origin so they tick in lockstep.
    started_at    timestamptz,

    -- Server timestamp of race finish. Set by either side
    -- when the race completes.
    ended_at      timestamptz,

    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 2. Indexes
-- ============================================================

-- Guest-side lookup: SELECT * FROM duo_races WHERE pair_code=$1
-- AND status='waiting'. Partial index keeps the index tiny —
-- only waiting rooms are queryable by code from outside the
-- host/guest pair, so the index doesn't bloat as finished
-- races accumulate.
CREATE INDEX IF NOT EXISTS duo_races_waiting_pair_code_idx
    ON public.duo_races (pair_code)
    WHERE status = 'waiting';

-- Host's own room lookup (for re-joining a paused pairing flow).
CREATE INDEX IF NOT EXISTS duo_races_host_user_idx
    ON public.duo_races (host_user_id);

-- Guest's own rooms.
CREATE INDEX IF NOT EXISTS duo_races_guest_user_idx
    ON public.duo_races (guest_user_id);

-- ============================================================
-- 3. updated_at trigger
-- ============================================================

-- Standard Postgres pattern — every UPDATE bumps updated_at.
-- Same shape as the trigger on `races` and `profiles`. If your
-- project already defines a generic `set_updated_at()` trigger
-- function, you can DROP this duplicate and use that one.
CREATE OR REPLACE FUNCTION public.duo_races_set_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS duo_races_updated_at ON public.duo_races;
CREATE TRIGGER duo_races_updated_at
    BEFORE UPDATE ON public.duo_races
    FOR EACH ROW
    EXECUTE FUNCTION public.duo_races_set_updated_at();

-- ============================================================
-- 4. Row-Level Security
-- ============================================================

ALTER TABLE public.duo_races ENABLE ROW LEVEL SECURITY;

-- Drop any old policies so re-running this file is idempotent.
DROP POLICY IF EXISTS duo_races_select_waiting ON public.duo_races;
DROP POLICY IF EXISTS duo_races_select_own ON public.duo_races;
DROP POLICY IF EXISTS duo_races_insert_self ON public.duo_races;
DROP POLICY IF EXISTS duo_races_update_host ON public.duo_races;
DROP POLICY IF EXISTS duo_races_update_join ON public.duo_races;
DROP POLICY IF EXISTS duo_races_update_guest ON public.duo_races;
DROP POLICY IF EXISTS duo_races_delete_own ON public.duo_races;

-- SELECT: any authenticated user can read a 'waiting' row.
-- This is how the guest looks up a room by pair_code without
-- knowing the host. Restricted to 'waiting' status so finished
-- rooms aren't browseable by random users with leaked codes.
CREATE POLICY duo_races_select_waiting ON public.duo_races
    FOR SELECT
    TO authenticated
    USING (status = 'waiting');

-- SELECT: host or guest can always read their own rooms,
-- including post-pairing (status='paired'/'racing'/'finished').
CREATE POLICY duo_races_select_own ON public.duo_races
    FOR SELECT
    TO authenticated
    USING (
        auth.uid() = host_user_id OR auth.uid() = guest_user_id
    );

-- INSERT: authenticated users can create a row only with
-- themselves as the host. Prevents one user from creating a
-- room under another user's identity.
CREATE POLICY duo_races_insert_self ON public.duo_races
    FOR INSERT
    TO authenticated
    WITH CHECK (
        auth.uid() = host_user_id
        AND status = 'waiting'
        AND guest_user_id IS NULL
    );

-- UPDATE: the host can update their own room at any time
-- (start race, finish race, abandon).
CREATE POLICY duo_races_update_host ON public.duo_races
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = host_user_id)
    WITH CHECK (auth.uid() = host_user_id);

-- UPDATE: an authenticated user can claim a 'waiting' room by
-- setting themselves as the guest. This is how the guest
-- joins. After the claim, subsequent updates go through the
-- "guest can update their own" policy below.
CREATE POLICY duo_races_update_join ON public.duo_races
    FOR UPDATE
    TO authenticated
    USING (
        status = 'waiting' AND guest_user_id IS NULL
    )
    WITH CHECK (
        auth.uid() = guest_user_id AND status = 'paired'
    );

-- UPDATE: the claimed guest can update the room (e.g. mark
-- finished from their side).
CREATE POLICY duo_races_update_guest ON public.duo_races
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = guest_user_id)
    WITH CHECK (auth.uid() = guest_user_id);

-- DELETE: host or guest can clean up their own rows (rarely
-- needed; the delete_user_account RPC handles per-user
-- cascade on account deletion, and abandoned rows can be
-- purged by a future scheduled job).
CREATE POLICY duo_races_delete_own ON public.duo_races
    FOR DELETE
    TO authenticated
    USING (
        auth.uid() = host_user_id OR auth.uid() = guest_user_id
    );

-- ============================================================
-- 5. Comment + grants
-- ============================================================

COMMENT ON TABLE public.duo_races IS
'§4.5 Tier 2 — coordination metadata for cross-city HYROX Doubles. Race-time events flow via Realtime broadcast, not this table; rows here are room state only.';

-- ============================================================
-- 6. Troubleshooting probes
-- ============================================================
--
-- Run these in the Supabase SQL Editor when the iOS app shows
-- "No open room found for that code" or "Code not found or room
-- is no longer waiting" even though the host clearly has a code
-- on screen. The two most common deploy-side failures are:
--
--   (1) Table exists but the RLS policies above were never
--       applied (an earlier deploy partially failed, or the
--       file got re-run with a typo'd policy name).
--   (2) Realtime publication isn't enabled for duo_races, so
--       the broadcast channel works but no one ever hears the
--       hello message.
--
-- A. Verify all expected RLS policies are present.
--    Expected: 7 rows (select_waiting, select_own, insert_self,
--              update_host, update_join, update_guest,
--              delete_own).
--
-- SELECT policyname, cmd
--   FROM pg_policies
--  WHERE schemaname = 'public'
--    AND tablename  = 'duo_races'
--  ORDER BY policyname;
--
-- B. Verify Realtime is publishing duo_races.
--    Expected: 1 row.
--
-- SELECT schemaname, tablename
--   FROM pg_publication_tables
--  WHERE pubname = 'supabase_realtime'
--    AND tablename = 'duo_races';
--
-- C. As an authenticated user (NOT the service-role key), see
--    what waiting rooms are visible to you. If this returns 0
--    while the iOS host clearly has a code on screen, the
--    `duo_races_select_waiting` policy isn't applied. Run the
--    `CREATE POLICY duo_races_select_waiting ...` block above
--    again to re-apply.
--
-- SELECT id, pair_code, status, created_at
--   FROM public.duo_races
--  WHERE status = 'waiting'
--  ORDER BY created_at DESC
--  LIMIT 5;
--
-- If A/B/C all look right and the iOS app still shows
-- "No open room found", the issue is almost certainly a real
-- typo in the code the guest is typing — the Phase 59
-- diagnostic (status-aware probe in CloudDuoSession.joinRoom)
-- will say "That room is already paired / in progress /
-- finished" if a real but non-waiting row exists.
