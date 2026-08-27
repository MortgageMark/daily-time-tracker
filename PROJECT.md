# Time Tracker — Project Handoff

**Read this first if you are a new chat session picking up this project.**
It replaces the older `PROJECT_DOCUMENTATION.md`, which contained stale paths
and leaked credentials. Do not trust that file.

- **Live:** https://dailytimetracker.com
- **Current release:** v12 (in `feature/day-editor-relabel`, not yet merged)
- **Last deployed:** **v9**, build `202608262001-dcb070b`
- **Status:** stable, in daily use

> **v10, v11 and v12 are committed but NOT deployed.** `master` was four
> commits ahead of `origin/master` as of 2026-08-27 and the push never
> happened, so the live site is still v9 — meaning the v11 stale-device sync
> protection is not actually protecting anything yet. Verify with
> `curl https://dailytimetracker.com/version.json` before believing any
> release claim in this file.

---

## 1. Where everything is

| Thing | Where |
|---|---|
| Local clone | `C:\Users\markn\OneDrive\Desktop\Claude Folder\daily-time-tracker` |
| GitHub | `https://github.com/MortgageMark/daily-time-tracker` (public) |
| Live site | https://dailytimetracker.com |
| Host | Netlify, site `incomparable-fox-92eba4`, auto-deploys from `master` |
| Database | Supabase project `vybypyeyzfgakenkotbw` |

The whole app is **one file**: `index.html` (~425 KB, ~150 top-level functions,
all CSS and JS inline). There is no build step and no framework. The Netlify
build command only stamps a version; it does not compile anything.

```
index.html                      the entire app
manifest.json                   PWA manifest
netlify.toml                    build command, cache headers, SPA rewrite
supabase-plans-migration.sql    already run; kept for reference / new envs
supabase-channel-attributes-migration.sql
                                RUN 2026-08-26. Channel attribute columns.
supabase-dayplans-daytype-migration.sql
                                NOT YET RUN - adds dayplans.day_type.
apple-touch-icon.png            180px, iOS home screen
icon-192.png / icon-512.png     manifest icons (512 doubles as maskable)
favicon-32.png                  browser tab
.gitignore                      ignores version.json, scratch files, local state
CLAUDE.md                       session orientation; points here
.claude/launch.json             local static-server config (port 8888)
```

### Credentials

**Do not paste tokens into files or chat.** The original documentation had a
live GitHub PAT and Netlify token sitting in plaintext; they were exposed and
should be treated as burned.

- **GitHub** — repo is public, so `clone` and `pull` need nothing. Only `push`
  needs auth, and the machine already has Git Credential Manager configured, so
  `git push` works without anyone handling a token.
- **Netlify** — not needed for normal work; deploys happen via GitHub push.
- **Supabase anon key** — public by design and already embedded in `index.html`.
  Row Level Security is what protects the data, not the key.

---

## 2. Running it locally

A `daily-time-tracker` entry exists in **two** `.claude/launch.json` files and
both work — which one applies depends on the working directory:

- `daily-time-tracker/.claude/launch.json` — used when the cwd is the repo.
  Committed, so the repo is self-contained.
- `Claude Folder/.claude/launch.json` — used when the cwd is the parent folder
  (the usual case). Adds `--directory daily-time-tracker`. That file also
  serves `mortgage-toolkit`, so do not edit it for this project's sake.

Both serve port 8888. Start it through the preview tooling rather than a raw
shell.

Manually, it is just a static server:

```bash
cd "C:\Users\markn\OneDrive\Desktop\Claude Folder\daily-time-tracker"
python -m http.server 8888
```

Then open http://localhost:8888.

- Windows uses `python`, **not** `python3`.
- Serve over `http://` — Supabase auth redirects misbehave under `file://`.
- Locally `BUILD_ID` stays as the literal `__BUILD_ID__` placeholder, so the app
  reports **"dev build"** and skips update polling entirely. That is correct.

---

## 3. Deploying

```bash
git checkout -b feature/whatever      # never commit straight to master
# ... work, commit ...
git checkout master
git merge --no-ff feature/whatever
git push origin master                # Netlify builds in ~2 minutes
```

**Bump `APP_RELEASE` in `index.html`** when cutting a release. The build stamps
the timestamp automatically; the release integer is manual and deliberate.

### What the build does

`netlify.toml`'s command rewrites `__BUILD_ID__` in `index.html` and writes
`version.json`:

```json
{"build":"202608260444-17919e2","release":3}
```

Format is `YYYYMMDDHHMM-<short commit>`, UTC.

### Verifying a deploy

Fetch `https://dailytimetracker.com/version.json` and confirm the build id
matches the commit you just pushed. Also confirm `__BUILD_ID__` no longer
appears in the served HTML — if it does, the build command did not run.

### Rolling back

```bash
git reset --hard <good-commit> && git push origin master --force
```

Known-good points: `7154b21` (pre-v1), `cb4b341` (v1), `3aa8db0` (v2),
`17919e2` (v3).

---

## 4. Architecture

### Storage model

Local-first. IndexedDB is the working copy; Supabase is the backup and the
cross-device channel.

```
IndexedDB "dtt2" v5
  profiles       user profiles (Mark, Tamara)  keyPath id
  channels       channels + subcategories      keyPath id
  sessions       tracked time                  keyPath id
  plans          reusable templates            keyPath id
  dayplans       one materialised day          keyPath id  ("<profileId>|<date>")
  day_notes      rating, notes, scores         keyPath date
  selected_plan  legacy date -> planId pointer keyPath date
  meta           lastProfile, acctUser         keyPath k
```

`channels`, `sessions`, `plans` and `dayplans` each carry a **`profile` index**
on `profileId`. If those indexes go missing, every `idbAll(store,"profile",…)`
throws and the whole app renders blank — see Landmines.

### Sync

```js
SYNC_STORES = ["profiles","channels","sessions","plans","dayplans"]
```

`runSync()` pushes dirty records then calls `pullRemote()`. Merge rule: a remote
row overwrites a local one only when the local row is **not** dirty and the
remote `updated_at` is newer or equal.

**`day_notes` and `selected_plan` do NOT sync.** They are keyed by date alone,
so two profiles on one device would collide. Fixing that needs the same
composite-key migration `dayplans` already got.

If a Supabase table is missing, the app notes it once, logs one warning, skips
it, and **retries after 10 minutes** — so running a migration starts syncing
without a reload.

### Channels

`order` is scoped to a sibling group: top-level channels order among
themselves, subcategories among siblings of the same parent. Moving a parent
therefore carries its children automatically. `parentChannelId` is `null` for
top-level.

### Channel attributes

Must/Will/Want, DRIP and the two Eisenhower axes are all one mechanism, not
three features. `CHANNEL_ATTRS` declares them as data and every picker and
report section is generated from it, so a fourth scheme is a few lines.

| Field | Values |
|---|---|
| `tier` | `must` / `will` / `want` |
| `drip` | `D` Delegate / `R` Replace / `I` Invest / `P` Produce |
| `urgency` | 1-5 |
| `importance` | 1-5 |

`channelAttr(ch,key)` resolves a value, falling back to the parent channel, so
a subcategory inherits its parent unless tagged itself. **Unset values are
stored as `null`, never `""`** - an empty string counts as "set" and would
break inheritance. The lookup carries a depth guard against a channel that
somehow became its own ancestor.

`HIGH_SCALE` (4) is the urgency/importance threshold for the quadrant view, so
4 and 5 read as high. The Priorities view reports untagged time explicitly
rather than dropping it, so coverage cannot be silently overstated.

`supabase-channel-attributes-migration.sql` **was run on 2026-08-26**, so
these four columns exist and sync normally.

The mechanism behind it is worth knowing, because the next migration relies on
it too. Supabase rejects an upsert naming a column it does not have and fails
the whole row, so `OPTIONAL_COLUMNS` / `rowForPush()` detect that once, retry
the push without those columns, and retry the full set every 10 minutes -
meaning running a migration starts the sync without a reload.

### Stale-device protection

A browser that has not been opened in a long time holds an old snapshot.
`pullRemote()` refuses to overwrite a local row marked `_dirty`, but the push
loop sent that row up regardless, so the stale copy won and good data was
destroyed. This was not theoretical: a dormant Safari was holding channels many
revisions out of date while Chrome was correct, one sync away from overwriting
everything.

`findStaleConflicts()` now runs before the push. It fetches the server's
`updated_at` for exactly the rows about to be pushed and flags any where the
server is newer than the local `_u` by more than `STALE_CONFLICT_MS` (5 min).
The user is then asked once - use the cloud version, decide later, or upload
anyway - instead of being silently overwritten.

Three details that matter if this is ever changed:

- **The threshold is deliberately generous.** `_u` comes from the device clock
  and `updated_at` from the server's, so a few minutes of skew must not read
  as a conflict. A genuinely dormant device is days or weeks stale.
- **It fails open.** If the check cannot run (offline, error, missing table)
  the push proceeds as before. A verification failure must not block syncing.
- **A row absent from the server is never a conflict** - that is just a new
  record that has not been pushed yet.

"Upload anyway" restamps `_u` to now, so those rows legitimately win rather
than being flagged again on the next sync.

**`doSignOut()` no longer pushes automatically.** It used to sync before
wiping, to avoid losing unsynced work - which made signing out the single most
dangerous thing to do on a stale browser. It now asks: upload, discard, or
cancel.

**`refreshFromCloud()`** (Settings > Refresh from cloud) is the safe reset for
a stale browser: it wipes local data and reloads WITHOUT syncing first. Sign-out
cannot do this job, because syncing first is the exact push being avoided.

### Non-working days

Marking a day Vacation / Holiday / Sick / Personal excludes it from adherence
scoring. Before this, a day off scored 0% Timing and 0% Budget against the
weekday template, so a week of leave dragged down every long-range average.

**The flag lives on `dayplans`, not `day_notes`.** day_notes is keyed by date
alone and does not sync, so two profiles on one device would share each other's
holidays and nothing would reach a second device. dayplans is already keyed
`profileId|date` and already syncs. Any future day-level flag belongs there for
the same reason.

- Time tracked on a non-working day **still records and still counts in
  totals** - only the score is skipped.
- **Clearing the stored scores IS the exclusion mechanism.** Every average
  checks for `matchScore`/`budgetScore` and skips a day without them, so no
  averaging code needed to change. `refreshDayScores()` returns null and calls
  `clearDayScores()` for a flagged day.
- Marking a day off after it was scored clears the stale numbers. The rating
  and notes are deliberately kept - they are a separate judgement.

**Marking a FUTURE day must not go through `ensureDayPlan()`.** Materialising a
day that early freezes whatever the template says today onto it, and if
`planState` has not loaded it would freeze an *empty* plan onto a real working
day. `setDayType()` writes a bare marker instead, and `dayPlanMaterialised()`
treats a record with no `planId` and no blocks as not yet materialised - so
`ensureDayPlan()` still fills in the real plan when the day arrives and carries
the flag across.

`supabase-dayplans-daytype-migration.sql` **has not been run yet.** Until it
does, the flag works on-device but does not sync.

### Which fields may be edited for a future date

The rule is not "no editing future dates" - that would block marking leave in
advance, which is the whole point. It splits by what the field means:

| Field | When |
|---|---|
| Star rating, notes | today and past only - retrospective |
| Day type, plan assignment | any date, including future |

### Plans: templates vs days

This is the most important concept in the app.

- **`plans`** are reusable templates ("Monday", "Heavy Pipeline Day"). Unlimited.
- **`dayplans`** are one materialised copy per profile per date.

Applying a template **copies** it into the day. Editing the day writes only to
that copy — the template is never touched implicitly. "Save to template" pushes
a day's edits back, behind a confirm.

**Copy-on-apply, not copy-on-edit.** Once a day exists it is frozen, so editing
a template later cannot rewrite past days or corrupt adherence history.

Today auto-materialises from the `selected_plan` pointer if present, otherwise
from the template whose name matches the weekday.

### Sessions crossing midnight

A session stores the date it **started** on (`date`), and that stamp never
changes. Before v4 a timer left running overnight behaved two ways at once:
the per-session clock on the tile counted straight through the night (it is
just `now() - startTs`, with no date filter) while today's totals ignored it
entirely (they filter on `date`, which still said yesterday). Stopping it
then wrote the whole overnight span onto **yesterday**, silently changing
that day's Budget and Timing scores.

`reconcileOpenSession()` now runs in two places: on load from
`reloadFromLocal()` (after the first paint, so its dialog appears over the
rendered app), and once per tick from the 1s interval so that an app left
open across midnight rolls over too. It guards its own re-entrancy.

- `splitSessionAcrossDays()` closes the session at `23:59:59.999` of its own
  day and opens a fresh one at `00:00:00.000` of the next, repeating until it
  reaches today. Each day then holds only the time that elapsed inside it.
- Anything running longer than `LONG_SESSION_MS` (8h) raises a `uiChoice()`
  prompt first: keep it, set the real end time, or discard it. At that length
  a forgotten timer is likelier than real work.
- **Discard zeroes the session rather than deleting it.** Deletes do not
  propagate to Supabase, so a deleted row can reappear on the next pull. A
  zero-length session syncs correctly and contributes nothing.

`uiChoice()` is a deliberate sibling of `uiDialog()`, not a third `kind`,
because `uiDialog` is hard-wired to two buttons and every other feature in
the app depends on it.

### Scoring

`computeDayScores(plan, dateKey, sessions)` is a pure function returning both:

- **Timing** — planned blocks where that channel actually ran. Time-sensitive.
  Stored as `day_notes.matchScore = {matches,total}`.
- **Budget** — planned minutes vs actual minutes per channel, regardless of
  when. Per-channel credit capped at planned, so overdoing one channel cannot
  mask skipping another. Stored as `day_notes.budgetScore`.

Both count **only elapsed blocks**, so an in-progress day is not scored against
hours that have not happened.

The Summary calls `refreshTodayScores()` on open, so it never shows a stale
snapshot left behind by the Tracker.

### Function map

| Area | Key functions |
|---|---|
| DB | `openDB`, `applySchema`, `schemaGaps`, `idbGet/idbPut/idbAll/idbDel/idbClear` |
| Sync | `runSync`, `pullRemote`, `dirtyRecords`, `toRow`, `fromRow`, `syncableStores` |
| Channels | `renderChannelSettings`, `buildChannelRow`, `moveChannel`, `dropChannel`, `deleteChannel`, `createDefaultChannels` |
| Plans | `renderPlanPageUI`, `ensureDayPlan`, `applyTemplateToToday`, `saveTodayToTemplate`, `setPlanSlot`, `todaysEffectivePlan` |
| Scoring | `computeDayScores`, `persistDayScores`, `refreshTodayScores`, `renderAdheranceComparison`, `adhCellHtml` |
| Dashboard | `renderGrid`, `switchTo`, `startSessionOnChannel`, `stopRunning` |
| Dialogs | `uiConfirm`, `uiPrompt`, `uiDialog`, `uiChoice` |
| Overnight | `reconcileOpenSession`, `splitSessionAcrossDays`, `promptSessionEnd`, `parseClockOnDay`, `endOfDay` |
| Versioning | `checkForUpdate`, `showUpdateBanner`, `fmtBuild` |

---

## 5. Landmines

Every one of these caused a real bug. Read before editing.

**Never use `confirm()` or `prompt()`.** They are unreliable outside a plain
top-level page: sandboxed frames return `false` without showing anything, and
`prompt()` throws outright. Use `uiConfirm()` / `uiPrompt()`, which are
promise-based and always work. This silently broke every plan action once.

**Never let `openDB` fail.** If `db` is null, every `tx()` throws
"Database not initialized" and the entire app renders blank with saves quietly
doing nothing — with no error shown. `openDB` now adopts a newer database
rather than rejecting it, and repairs missing stores, missing indexes and a
stale `dayplans` keyPath in place. Do not simplify that logic.

**Do not test around the thing that is broken.** A test that stubs `confirm()`
to return `true` passes while the feature is dead. Drive real UI elements.

**Never change a table's column count in the Summary.** Header and body counts
must match or the layout breaks. Adherence cells return inline HTML only, never
`<td>`/`<tr>`. There are five consumers of `matchScore`; keep its
`{matches,total}` shape so changes stay additive.

**Historical data predates `budgetScore`.** Anything rendering it must omit the
Budget line when absent rather than printing `undefined`.

**Form controls must be ≥16px on mobile** or iOS zooms the page on focus.

**A missing column and a missing table look alike.** Supabase reports a
missing column as PGRST204 with "...in the schema cache" in the message -
which is exactly what `isMissingTable()`'s regex matches. It is checked first
in the push loop, so before this was guarded a missing column marked the whole
*table* missing and stopped that store syncing for 10 minutes. `isMissingTable`
now defers to `isMissingColumn` first. Keep that ordering.

**Never let `<body>` lose its background-color.** The login screen is
`position:fixed` and `.app` is `display:none` until sign-in, so body can
collapse to zero height. A gradient with a zero-height positioning area paints
nothing, and with no color behind it the canvas falls back to white.

**Never use `apple-mobile-web-app-status-bar-style: black-translucent`.** It
lifts the web view up under the status bar without extending its height, so
the view ends up short at the BOTTOM by exactly the status-bar height, leaving
a dead band the page cannot paint into. Use `black`. This cost five releases
to find, because it presents as a styling bug and is immune to every styling
fix. The diagnosis that finally worked:

- `screen.height` minus `innerHeight` equalled `safe-area-inset-top` exactly
- the bottom bar could be dragged and would vanish at a boundary above the
  screen edge - content leaving the viewport, which no CSS can cause
- `GAP BELOW BAR` measured 0px throughout and was actively misleading: the bar
  really was at the bottom of the web view; the web view was not at the bottom
  of the screen

**When a fix does not move a visible symptom, re-measure the symptom rather
than refining the fix.** Four fixes in a row landed, were individually
correct, and changed nothing the user could see. Each one should have been
treated as evidence the diagnosis was wrong. Ask for on-device numbers early:
`env(safe-area-inset-*)` resolves to 0 in a desktop emulator, so anything
reasoned about rather than observed is guesswork. A temporary diagnostic panel
(removed in v10, see git history for `displayDiagnostics`) settled in one
round trip what four releases of inference could not.

**Watch for duplicate function declarations.** A second `moveChannel` silently
shadowed the new one. `renderPlanSelect` is still defined twice — both are dead,
nothing calls them, left alone deliberately.

**Inline `onclick` handlers need `window.foo`.** `const` declarations do not
attach to `window`; function declarations do.

**Escaping.** Any user-supplied string in generated HTML goes through
`escapeHtml()`. Verified with hostile channel and template names.

---

## 6. Known limitations (accepted)

- `day_notes` and `selected_plan` are keyed by date only — two profiles on one
  device share them. Needs a composite-key migration.
- Deletes do not propagate to Supabase; deleted rows can return on next pull.
- Separate browsers keep entirely separate IndexedDB stores, so the same
  account can look completely different in Safari and Chrome on one phone.
  That is expected. What used to make it dangerous was fixed in v11 - see
  Architecture > Stale-device protection.
- iOS caches the home screen icon and name at install. Changing them requires
  removing and re-adding the shortcut, once.
- Supabase's built-in mailer is rate-limited to a few messages an hour and often
  lands in spam. Fine for testing, needs real SMTP before onboarding users.
- No timezone handling for *travel*: a session is split and stamped using
  whatever local time the device reports, so crossing a timezone mid-session
  shifts where the day boundary falls. Sessions crossing **midnight** are
  handled correctly as of v4 - see Architecture > Sessions crossing midnight.
- `ensureObjectStores()` is dead code that would recreate stores without
  indexes. Never called. Delete it if you are ever cleaning up.

---

## 7. Backlog

Captured 2026-08-26. **Backfill, Must/Will/Want, Urgent/Important and DRIP all
shipped in v4** - 7.1, 7.3, 7.4 and 7.5 below are kept for context but are
done. Two items remain, and both need a conversation before any code:

- **7.2 Perfect Week** - scope was partly garbled; confirm what it is first.
- **7.6 Coach access** - crosses an account boundary; needs a security design
  session of its own.

### 7.1 Backfill and retroactive editing  — *SHIPPED v4* — *highest practical value*
Add or correct time for a **past** day: "I forgot to track yesterday, let me
enter it now." Today the app is strictly live-timer driven.

Needs: a date picker on the Tracker/Summary, manual session create/edit/delete
with start and end times, and recomputation of that day's scores via
`computeDayScores(plan, dateKey, sessions)` — which already accepts an arbitrary
`dateKey`, so the scoring half is done.

Watch: `refreshTodayScores()` only refreshes today; backfilling a past day must
persist that day's scores too.

### 7.2 Perfect Week
A separate planning surface — possibly its own app — that models an ideal week
and feeds the tracker. The tracker's `plans` templates are effectively a
weekday-shaped version of this already, so the question is whether Perfect Week
*becomes* the template source or stays separate and syncs into it.

**Needs a conversation before any code.** Mark's description was partly cut off;
confirm scope, whether it is one app or two, and where it lives.

### 7.3 Must / Will / Want tiers  — *SHIPPED v4*
Tag every channel with one of three commitment levels:

| Tier | Meaning | Mark's examples |
|---|---|---|
| **Must** | Non-negotiable, cannot skip | corporate meetings, the recurring planning meeting |
| **Will** | Committed to doing | core daily work |
| **Want** | Lower priority, only if time allows | marketing |

Then report time by tier, and likely score adherence by tier — missing a Must
should read very differently from missing a Want.

Implementation: one field on the channel record, a picker in the channel
editor, grouping in reports. Small schema change, meaningful reporting change.

### 7.4 Urgent / Important scoring → Eisenhower quadrant  — *SHIPPED v4*
Rate each channel 1–5 on **urgency** and 1–5 on **importance**, then plot time
spent across the four Eisenhower quadrants. The coaching value is seeing how
much time lands in "urgent but not important."

Two integer fields per channel plus a quadrant visualisation. Composes
naturally with Must/Will/Want — likely the same editor screen.

### 7.5 DRIP categorisation  — *SHIPPED v4*
Assign channels to DRIP buckets and report time per bucket.

- **D** — Delegate
- **R** — Replace
- **I** — Invest
- **P** — *confirm with Mark; he was unsure. Likely "Produce".*

Structurally identical to Must/Will/Want: one field, one picker, one report.
If all three tagging systems ship, build **one generic channel-attribute
mechanism** rather than three bespoke ones.

### 7.6 Coach / manager access to summaries
Give a coach or boss read-only visibility into summaries.

This is the largest item by far — it is the first feature that crosses an
account boundary, so it needs real design:
- Share model: per-coach invite? read-only link? scoped Supabase role?
- New RLS policies; current policies are strictly `owner = auth.uid()`.
- What is shared — summaries only, or sessions and notes too?
- Revocation.

Do not bolt this on. It deserves its own session.

### 7.7 Stale-device sync protection — *FIXED in v11*

Shipped. See Architecture > Stale-device protection for how it works and what
to preserve if it is ever changed.

One piece of the original analysis was deliberately NOT done: the underlying
merge rule is still asymmetric - local always wins on push, the server never
wins over a dirty row on pull. v11 gates the dangerous case rather than
resolving that asymmetry. If conflicts ever become common rather than
exceptional, that is the thing to revisit.

### What is left

1. **Perfect Week** — needs a scoping conversation first
2. **Coach access** — needs a security design session

Both need a conversation before any code. Neither is a bug.

Items 1, 3, 4 and 5 shipped in v4. The generic channel-attribute mechanism
they share is `CHANNEL_ATTRS` - see Architecture > Channel attributes.

---

## 8. What shipped 2026-08-25/26

**v1** — sign-up, forgot password, set-new-password; sign out moved to the
avatar menu; local data cleared on account switch; login race fixed
(`getSession()` can transiently return null during token refresh); subcategory
drag/drop (documented as done but never wired); up/down arrows; expand/collapse;
true reordering instead of a two-item swap; plan drop targets fixed (chips had
`ondragstart` but slots had no `ondragover`/`ondrop`, so the browser refused
every drop); plan templates vs days; plan CRUD rendered; plans and dayplans
added to sync; in-app dialogs; Budget score; PWA icons and manifest linked for
the first time; version stamping and update banner; standard default channels
replacing hardcoded personal profiles.

**v2** — hotfix: `openDB` now repairs broken local databases instead of failing
blank, and any remaining boot failure shows an explanatory panel with a safe
"reset this device" option.

**v3** — larger mobile type, 16px form controls, pinch-zoom re-enabled.

**v4** — two fixes. Sessions left running past midnight are now split at the
day boundary instead of counting into today while scoring against yesterday,
and anything running over 8h asks before it is counted. Separately, the white
band at the bottom of the screen on iOS: `<body>` could collapse to zero
height (the login screen is `position:fixed`), a gradient with no height
paints nothing, and with no background-color behind it the canvas fell back
to white. html and body now both carry a height and a solid background.

v4 also carries the first three backlog items. **Backfill:** a Day Editor
(avatar menu) walks any past date and supports create / edit / delete, with
the day rescored after every change - `refreshTodayScores()` is now a wrapper
over `refreshDayScores(dk)`. Deleting voids and zeroes a session rather than
removing it, because deletes do not propagate to Supabase and the row would
return on the next pull. Overlaps are confirmed rather than silently accepted.
**Channel attributes:** Must/Will/Want, DRIP and Urgency/Importance built as
one generic mechanism, with a Priorities report and an Eisenhower quadrant.
**Non-working days:** Vacation/Holiday/Sick/Personal on any date including
future ones, excluded from adherence scoring; star rating and notes extended to
any past day; the Summary's lookback range no longer accepts future dates and
its inputs raised to 16px.

**v5-v9** — chasing one symptom: a dead band below the bottom bar in the
installed iOS PWA. v5 pinned `.app` with position:fixed/inset:0 (real fix, the
measured gap went to 0). v7 and v8 rebalanced the bar's safe-area padding
(real, still not it). v6 added a temporary on-device diagnostic, which is what
finally produced the numbers that identified the actual cause in v9:
`apple-mobile-web-app-status-bar-style: black-translucent` was making the web
view itself shorter than the screen. Also in this run: future days can no
longer be star-rated (guarded at `saveDayRatingAndNotes`, the single choke
point the four separate star renderers had drifted away from), ratings can be
cleared, and the day-type picker appears on every Summary row.

**v10** — removes the diagnostic panel; no user-facing change.

**v11** — fixes backlog 7.7. A stale device can no longer silently overwrite
newer data: the push is gated by a comparison against the server's
`updated_at`, sign-out no longer force-pushes, and Settings gains "Refresh from
cloud" as the safe reset that sign-out could never be.

**v12** — rebuilds the Day Editor as a **timeline**, after a first attempt as a
card list with nudge buttons was correct but unpleasant to use. The lesson is
worth keeping: the list was technically complete and still failed, because a
list cannot show a gap and a day is a shape.

The day is drawn to scale against an hour rail (`tlRange()` covers the planned
working hours widened to whatever actually happened, so a 6am start is not
clipped). Each block is its channel's colour, labelled with its exact start,
end and duration. Gaps appear as dashed regions with the untracked time named.

- **Tap a block** to change its channel, from a sheet rather than an inline
  expansion — expanding inline would move everything below it and break the
  geometry the timeline exists to show.
- **Drag the grip on an edge** to move when a block started or stopped. Every
  drag lands on a 5-minute grid and jumps to a neighbour's edge within 10
  minutes, so closing an 8-minute gap needs no precision. Mark asked for this
  explicitly: do not make him be exact.
- **`resolveEdgeDrag()` is pure and is the whole model.** It takes the day and
  one proposed edge time and returns what the day becomes. Overlaps are
  unreachable *by construction* rather than validated after the fact: a block
  dragged into its neighbour pushes that neighbour back, and one dragged clean
  past a neighbour's far edge absorbs it — the "I left the timer running and
  it was really all one thing" case. The preview during a drag and the commit
  on release run the same function, so what is shown is what is saved.
- A **running block is never absorbed or pushed**; a drag stops short of it.
- **Every gap carries a `+`** that fills it with one channel, taking the whole
  gap — guessing at a partial fill would be inventing data. It is pinned to the
  right of the gap because the two drag grips own the middle of a short seam.
- **The rail before the first block and after the last one also gets a `+`**,
  so a day can be extended at either end. That space is deliberately *not*
  drawn as a dashed "untracked" region: an empty afternoon is not untracked
  time, it is simply the end of the day. These two add **at most an hour**
  (`TL_EDGE_ADD_MS`), unlike a real gap which fills exactly — a gap has data on
  both sides so its length is a fact, whereas the rail's far edge is only the
  plan's boundary. Adding again after that is one more tap, since a fresh `+`
  appears past whatever was just added.
- **Dragging a block's body slides the whole block**, after a 280ms hold on
  touch. The hold is not optional: without it every attempt to scroll the day
  would pick up whatever block sat under the thumb. A body drag clamps at its
  neighbours and **never absorbs one** — an edge drag is a deliberate reach for
  a grip, but a body drag starts anywhere on the block, and losing a neighbour
  to a clumsy thumb would be unrecoverable.
- Because pointer events cannot cancel a scroll iOS has already begun, a
  document-level `touchmove` listener refuses the scroll for as long as a drag
  is live. That listener is the reason the hold works at all.
- **Overlaps are refused in the "Exact times…" form too.** It used to warn and
  then offer "Save anyway", explicitly permitting double-counted minutes. That
  form was the last remaining way to create an overlap, and it is now closed —
  so no path in the app can put two channels in the same minute.
- Absorbed blocks are voided and zeroed, never deleted — deletes do not
  propagate to Supabase and the row would return on the next pull.

Verified on a seeded fixture at 375px by dispatching real pointer events at the
handles: magnet (a 38m gap snapped shut exactly), push (a neighbour shrank
rather than overlapping), absorb (the swallowed row voided with `durMs` 0), the
start-edge drag, and **no overlapping pair anywhere in the day afterwards**.

This replaced `buildSessionCard` / `buildSessionPanel` / `buildBoundaryRow` and
`moveBoundary` / `mergeSessions`, all removed. Merging is now just dragging one
block over another. `openSessionEditor()` survives untouched as "Exact times…",
still the way to type a precise time.

Round two of v12, after Mark used it:

- **A re-render no longer scrolls the day back to the top.** Every edit rebuilds
  the whole Day Editor, which threw the reader back to 8am after they added
  something at 6pm. `renderDayEditor()` now carries `#dayEditorBody`'s
  `scrollTop` across the rebuild.
- **The edge `+` is always offered**, even when the day already reaches the ends
  of the rail. The rail is the *planned* day, not the limit of the day: adding
  before 8am or after 6pm simply widens it on the next render, because
  `tlRange()` already covers whatever exists. Bounds are the real midnights
  (and the present, on today), not the plan. `TL_PAD` gives the rail 34px of
  headroom top and bottom so a flush-to-the-edge `+` is not clipped.
- **Avatar menu**: rows are `avatarMenuItem()`, with a 14px gap between icon and
  label and `filter:grayscale(1)` on the glyph. The emoji stay emoji - a
  grayscale filter was far cheaper than adopting an icon set. The sync dot is
  deliberately still coloured: it is a status, not an icon.
- **The subcategory sheet uses the parent's colour**, as gradient tiles in a
  grid rather than a stack of identical blue bars, so it reads like the
  dashboard it was opened from. Subcategories may carry their own colour; it is
  ignored here on purpose. "Generic" is outlined instead of filled, because it
  is the same channel rather than a sibling.
- **"Apply to today" greys to "Applied"** once today already matches the chosen
  template, and returns to blue the moment re-applying would change something -
  a different template picked, or the day edited away from its template.
  `syncApplyTodayBtn()` runs on render and on every dropdown change.

---

*Written 2026-08-26 by Claude (Opus 5) after the v1–v3 session.*
*Updated 2026-08-27: v12 Day Editor timeline, and the deploy-status
correction at the top.*
