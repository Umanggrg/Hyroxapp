# Resume-from-kill test plan

Manual checklist for verifying the resume flow works end-to-end. Do this on
your iPhone (real device preferred, but sim is fine for most cases). Each
case documents exact steps and the expected outcome; mark them off as you go.

Force-kill on iPhone: **swipe up from the bottom, hold**, then swipe the
Hyroxapp card up to dismiss. The app process terminates immediately. On the
sim, hit the square button in the sim toolbar to go home, then the list
icon, then swipe the app card up.

Terminology
- **"Resumable state"** = the app found an unfinished Race and shows the
  ResumePromptView on next launch.
- **"Active race"** = race is currently running on screen.

---

## 1. Baseline smoke test (happy path)

**Purpose**: confirm the app works end-to-end with no killing involved.

- [ ] Start a race
- [ ] Tap Next Station through all 16 stations, hold-to-finish on the last
- [ ] Summary shows total time and per-station splits
- [ ] Tap Done — returns to pre-race screen
- [ ] History tab shows the race as a new card
- [ ] Profile tab shows Races: 1, PB updated

**If this fails**, the baseline is broken and nothing below matters.

---

## 2. Force-kill immediately after start

**Purpose**: simplest resume case — race started but no splits yet.

- [ ] Start a race
- [ ] Wait 5-10 seconds (let the timer tick)
- [ ] **Force-kill the app**
- [ ] Relaunch
- [ ] ResumePromptView appears showing "Unfinished Race"
- [ ] Hero time reads something near 0 (the elapsed at kill moment)
- [ ] Current station shown is "1km Run"
- [ ] Tap Resume
- [ ] Race screen loads with the big timer displaying elapsed since
  original start (includes the blackout — if you were away for 30s, timer
  reads your prior 10s + 30s = 40s)
- [ ] Current station is "1km Run"
- [ ] Tap Next Station — advance works cleanly

---

## 3. Force-kill mid-race with multiple completed splits

**Purpose**: the most common real-world resume — user is deep in a race
when something interrupts.

- [ ] Start a race
- [ ] Advance through stations 1, 2, 3, 4, 5 (record the timer values
  displayed when you advance each so you can verify later)
- [ ] Partway through station 6, **force-kill**
- [ ] Relaunch
- [ ] ResumePromptView shows
- [ ] Hero time roughly matches station-5 finish time
- [ ] Current station shown is the one in progress at time of kill
- [ ] Tap Resume
- [ ] Splits chip in top-left reads "5 SPLITS"
- [ ] Tap chip — splits sheet shows all 5 completed splits with correct times
- [ ] Close sheet
- [ ] Current station matches the one you were in
- [ ] Tap Next Station — new split appears in splits sheet with the
  correct startedAt (the segment start, which pre-dates the blackout)

---

## 4. Force-kill during final station

**Purpose**: the hold-to-finish boundary case.

- [ ] Start a race, advance all the way to station 16 (Wall Balls)
- [ ] Partway through wall balls, **force-kill**
- [ ] Relaunch
- [ ] ResumePromptView shows
- [ ] Current station shown is "Wall Balls"
- [ ] Tap Resume
- [ ] Race screen shows Wall Balls, "Up next: Final station" label
- [ ] Button is "Hold to Finish" (not "Next Station")
- [ ] Hold to finish → summary shows, race lands in History

---

## 5. Force-kill after finishing but before summary dismissed

**Purpose**: `endedAt` is set on the race, so resume should NOT offer it.

- [ ] Start a race, complete all 16 stations (hold-to-finish)
- [ ] Summary screen is now showing
- [ ] **Force-kill** without tapping Done
- [ ] Relaunch
- [ ] **No ResumePromptView appears** (because `endedAt` is set, the
  race is not "unfinished")
- [ ] App opens to pre-race screen
- [ ] History tab shows the finished race

If you see ResumePromptView here, it's a bug — finished races shouldn't
be resumable.

---

## 6. Discard path

**Purpose**: confirm discard actually deletes the race row.

- [ ] Start a race, advance 2-3 stations, force-kill
- [ ] Relaunch
- [ ] ResumePromptView shows
- [ ] Tap Discard
- [ ] App opens to pre-race screen (no active race)
- [ ] History tab does NOT contain the discarded race
- [ ] Force-kill immediately, relaunch
- [ ] **No ResumePromptView** (the row was deleted)

---

## 7. Abandon (cancel X) in an active race

**Purpose**: same as discard but from inside a live race.

- [ ] Start a race, advance 2-3 stations
- [ ] Tap the X in the top-right
- [ ] Alert asks to confirm — tap Cancel Race
- [ ] App returns to pre-race screen
- [ ] History does NOT contain the abandoned race
- [ ] Force-kill, relaunch
- [ ] **No ResumePromptView**

---

## 8. Orphan cleanup

**Purpose**: verify the purge logic in `purgeOrphanedUnfinishedRaces` works
(prevents orphaned rows accumulating from repeated force-kills).

This is hardest to test manually because you'd need to game the system
— easier to trust the unit tests + code review. But if you want to
exercise it:

- [ ] Start race A, force-kill (orphan 1)
- [ ] Relaunch, tap Discard on the resume prompt (orphan 1 deleted)
- [ ] Start race B, force-kill (orphan 2)
- [ ] Relaunch, tap Resume (orphan 2 now is your active race)
- [ ] Complete and finish race B
- [ ] Open History — should contain only race B, no zombie entry
  from race A

---

## 9. Soft background (NOT force-kill)

**Purpose**: the app should NOT show a resume prompt for a soft
background — it should just resume in-place.

- [ ] Start a race, advance 2 stations
- [ ] Swipe up (home gesture) — app goes to background
- [ ] Wait 10-30 seconds
- [ ] Tap the Hyroxapp icon to return
- [ ] **No ResumePromptView** — you're back on the live race screen
- [ ] Timer has ticked forward correctly (includes the background time)
- [ ] Next Station still works

---

## Known intentional behaviors (not bugs)

- **Timer includes blackout time**. If you kill the app mid-run and
  relaunch 10 minutes later, the race timer reads +10 minutes. This is
  by design — CLAUDE.md §6 says the timer reflects wall-clock elapsed
  since the original start. The ResumePromptView's hero time shows the
  elapsed at the last split, not the current wall-clock elapsed; that's
  intentional (it tells you "this is where you left off").

- **If you finish a race and close the summary by force-killing**, the
  race still persists to History. The summary UI state is not persisted
  — only race data is.
