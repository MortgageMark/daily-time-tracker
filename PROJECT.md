# Time Tracker — Project Handoff

**Read this first if you are a new chat session picking up this project.**
It replaces the older `PROJECT_DOCUMENTATION.md`, which contained stale paths
and leaked credentials. Do not trust that file.

- **Live:** https://dailytimetracker.com
- **Current release:** v24
- **Last deployed:** v24, 2026-08-27
- **Status:** stable, in daily use

> **Verify before believing any release claim in this file.** It has been
> wrong twice. `curl https://dailytimetracker.com/version.json` settles it.
> v10-v12 sat undeployed for a day because a push was never made, and then
> because Netlify failed at *Initializing* - before the build command runs,
> with `netlify.toml` byte-identical to the last good deploy. A Retry
> cleared it. If it recurs, the detail is inside the Initializing row;
> suspect a retired build image or repo access rather than the code.

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
supabase-plans-migration.sql    RUN. Creates plans + dayplans.
supabase-channel-attributes-migration.sql
                                RUN 2026-08-26. Channel attribute columns.
supabase-dayplans-daytype-migration.sql
                                RUN 2026-08-27. Adds dayplans.day_type.
supabase-channels-joy-drain-migration.sql
                                RUN 2026-08-27. Adds channels.joy/.drain.
supabase-plan-window-migration.sql
                                NOT YET RUN - per-plan day window.
supabase-sessions-note-migration.sql
                                NOT YET RUN - adds sessions.note.
supabase-plans-assigned-weekday-migration.sql
                                NOT YET RUN - Perfect Week weekday link.
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
| `joy` | 1-5, 5 = loves it |
| `drain` | 1-5, 5 = wipes you out |

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

`supabase-dayplans-daytype-migration.sql` **was run on 2026-08-27**, so the
flag syncs. It failed the first time with `relation "public.dayplans" does not
exist` because it was run against the wrong Supabase project - check the ref in
the address bar first; that error means nothing was changed.

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

### Light and dark

The app was dark-only, and what made it dark-only was **~28 colours hardcoded
outside `:root`** rather than any structural problem. Those are now named
variables (`--field`, `--glass`, `--glass2`, `--scrim`, `--glow`, `--barbg`,
`--bad-ink`) and `:root[data-theme="light"]` overrides the lot.

- **Channel colours are deliberately not themed.** They are the user's data,
  and every surface that paints one already picks its text with
  `contrastInk()`, so tiles and timeline blocks work in both themes untouched.
- **The choice is device-local** (`localStorage`, key `dtt-theme`), not a
  profile field: which look someone wants depends on the screen in front of
  them, and a profile field would sync a phone's night mode onto a desktop.
- **A tiny script in `<head>` applies it before `<body>` exists**, so a reload
  never flashes dark and then corrects. It reads the same key. Both it and
  `currentTheme()` fall back to dark if `localStorage` throws.
- The toggle lives in the avatar menu and **names the mode it will switch to**.
  It is the one menu row that does not dismiss the menu, so the theme can be
  flipped and flipped back while looking at it.
- `apple-mobile-web-app-status-bar-style` is still `black` and **must stay
  that way** in both themes - see Landmines. Only the `theme-color` meta moves.

Two traps found while doing this, both worth remembering: a pale red
(`#fca5a5`, `#f87171`) that reads fine on a dark panel is invisible on a white
one - hence `--bad-ink`; and `.bottombar` carried its own `#0a101c`, which no
search for the other literals would have found. When theming, sweep for
`background:#...` across the whole file rather than trusting a list.

### Polish round, 2026-08-27

- **The Tracker's four columns are four separate stacks**, not a table, so one
  row growing in one column silently pushed that column out of step with the
  other three - which is what "the spacing gets off" was. Rows are now a fixed
  `height:36px` with `overflow:hidden`, and the channel chips ellipsis instead
  of wrapping. Verified: 20 rows per column, every row 36px, identical first
  and last offsets across all four. **If you ever add content to one of those
  cells, keep the fixed height.**
- Subcategory tiles centre their label on both axes.
- Channels now sits above Priorities in the avatar menu, and both the Channels
  and Settings page headers lost their glyph - the header already says what
  the page is.
- **The Priorities page opens with an explicit "completely optional"** note and
  a button through to Channels, where the tags are actually edited. It read
  like something you were failing to fill in.
- **Summary Week Overview tags Saturday and Sunday "Weekend."** This is a
  *label only* - it does not change scoring. Weekends usually score nothing
  anyway, because `todaysEffectivePlan()` finds no template matching that
  weekday. If weekends should be excluded from adherence the way leave is,
  that is a separate change to `refreshDayScores()`.
- **Both Summary tables gained a "Day type" column.** The select used to be
  jammed under the date in the Day cell. Header and body counts were moved
  together - see Landmines; this is exactly the trap that warning is about.

### Timeline zoom, and why blocks are drawn at their true height

A busy hour used to be unusable, and worse than it looked. `buildTimeline()`
floored every block at 18px so short ones stayed visible, which meant a
six-minute block claimed nearly three times its real span. Measured on ten
six-minute blocks in one hour: **nine of the ten pairs visually overlapped, and
all ten drag handles sat within 20px of each other**, stacked. Height had
stopped meaning duration, and the thing under your finger was not the thing you
were aiming at.

The fix is honest geometry plus a zoom, not a bigger minimum:

- Blocks render at their true height (floor of 2px, so a sliver is still
  visible). The label appears at >=24px and the times at >=42px; below that the
  colour bar alone says which channel it is.
- `TL_PX_PER_MIN` is now derived from `tlZoom` (1x / 2x / 4x, persisted in
  localStorage). Everything already positions through `tlY()`, and the drag
  maths works in deltas, so nothing else changed. At 4x a six-minute block is
  27.6px and handle collisions drop to **zero**.
- `zoomTimeline()` measures which moment is at the centre of the viewport,
  rescales, then puts that moment back. Without it, zooming throws the reader
  hours away from what they were looking at.

**A fisheye was deliberately rejected** - auto-expanding dense hours, or
tap-an-hour-to-expand. Both break linearity, and linearity is the entire reason
the timeline beats the old list: height means duration, at a glance. A view
where a 20-minute block can look larger than an hour is a worse confusion than
scrolling.

Pinch-to-zoom was left out for now. The buttons are testable here; a two-finger
gesture would interact with the existing pointer capture and the document-level
`touchmove` guard, and none of that can be verified without a real device.

**The magnet must never apply to an edge that is already flush.** This shipped
broken and is easy to reintroduce. The 10-minute magnet exists so that dragging
*toward* a neighbour closes the gap exactly. Applied unconditionally it does the
reverse: on a boundary the two blocks already share, every drag within 10
minutes snaps straight back, in both directions, so a contiguous day cannot be
nudged at all. It looked like "dragging down is broken" because the one edge
that still moved freely was the first block's start, which has no neighbour to
stick to. `resolveEdgeDrag()` and `resolveBlockMove()` now check whether the
edge was already touching before applying the magnet.

Zoom always opens at 1x. It is a tool for one crowded hour, not a preference,
so it is deliberately not persisted - though it does survive day navigation
while the editor stays open.

**Any view that rebuilds itself on every edit must carry the scroll across.**
This has now been fixed twice - the Day Editor, then the Summary - and the next
full-page view will have the same problem. `openCombinedSummary()` re-renders
the entire page for a rating, a note or a day-type change, so a change made in
the Complete History Log threw the reader back to the top.

Two details specific to the Summary:

- **Restore runs twice.** The history log is populated in a `setTimeout`, so
  immediately after the main content lands the container is still short and a
  large `scrollTop` gets clamped. `restoreSummaryScroll()` is called again once
  the log has rendered.
- **`origStage` had to be guarded.** It was captured unconditionally, so every
  re-entry - every edit - recaptured the summary as the thing to return to, and
  Home would "close" the summary back into the summary. It is now captured only
  on first entry.

### Profiles are hidden, not removed

The multi-profile UI is gone as of v14: no switcher in the avatar menu, and the
"New profile" sheet - which nothing ever opened, so it was already unreachable -
is deleted along with its create handler. The `Settings` and `Dashboard` headers
no longer append the profile name.

**The model is untouched and must stay that way.** Every store carries
`profileId` and a `profile` index, `runSync()` scopes by it, and every
`idbAll(store,"profile",...)` depends on it. Removing it would be a migration
across IndexedDB and Supabase both, for no gain. `seedIfEmpty()` still creates
exactly one profile and `loadProfile()` still runs at boot; there is simply no
route to a second one.

Verified with two profiles deliberately present in the database: the menu shows
no switcher and no profile names, and Settings and Dashboard both open cleanly
(their name spans were removed, so the assignments that filled them had to go
too or they would throw on null).

Bringing the feature back needs a switcher here **and a rename**, which never
existed - that missing rename is half the reason it was hidden.

### Day Editor layout, v14

Reordered around what people actually come here to do, which is fix times.

- The header is one row: `‹ [date] › Today`, with the pretty date beside it.
  **Home was removed** - the bottom bar already goes to the dashboard, so it was
  a second way to do the same thing occupying a whole row on a phone. Today
  keeps its greyed-out state on today itself.
- **Day type moved to the foot of the page**, behind a rule. It used to lead,
  which put the rarest action first. It still leads on a *future* date, where
  marking leave in advance is the only thing you can do.
- The paragraph explaining the timeline is gone, and the section is labelled
  **Zoom** rather than Sessions, because the control beside it is the zoom and
  pressing one teaches it faster than prose. The label falls back to "Sessions"
  on an empty day, where there is nothing to zoom.

### Day Editor chrome, v15

- **Zoom lives in the header now.** The body scrolls; the control you reach for
  when an hour is crowded must not scroll away with it. On a narrow phone the
  header wraps to two rows, which is fine — the header is outside the scroll
  container, so both rows stay put.
- The pretty-date label ("Wed, Aug 26") is gone; the date input beside it
  already says which day you are on.
- **The fixed footer is gone; the totals moved into the page.** "+ Add session"
  was a fourth route to something the `+` on any gap or either end of the rail
  already does, and a permanently pinned bar was not worth the height on a
  phone. The day total, Timing and Budget line now sits at the end of the
  scrolling content instead. `openSessionEditor(dk,null)` is unreachable as a
  result - the modal is still used for editing, so its "Add session" title
  branch is simply never chosen.
  **`refreshDayScores(dk)` does more than feed that line: it persists the
  day’s scores.** Removing it along with the display would quietly stop a
  browsed day being rescored.

### Tracker date navigation, v16

`openPlanAdherence()` hardcoded `todayKey()` twice. It is now split into
`openPlanAdherence(dk)` (entry) and `renderPlanAdherence()` (repaint), with
`adhDate` holding the day being viewed, so the Tracker walks back through days
the way the Day Editor does. `renderAdheranceComparison()` already took a
`dateKey` and derived everything from it, so it needed no change; the Match
column fills in completely on a past day because every block has elapsed.

**The stage snapshot is captured once, on entry, and guarded.** Tapping Tracker
while already on the Tracker would otherwise recapture the tracker as the thing
Home returns to - the exact trap `openCombinedSummary()` hit. Verified by
re-entering three times and confirming Home still lands on the dashboard.
**Any full-page view that can be re-entered needs this guard.** That is now
three of them.

Also: the Day Editor shows the weekday beside the date, because a native date
input renders `08/27/2026` and cannot be told to include it; and the zoom
buttons are captioned "Zoom" so `1x 2x 4x` is not a riddle.

### Today button, v17

On both the Day Editor and the Tracker, Today is pinned to the right edge and
**blue when tapping it would change something, grey and disabled when you are
already on today**. The colour carries the whole message; nothing else had to
say it.

Pinning it needed a wrapper rather than a spacer: the left cluster (arrows,
date, weekday, zoom) is its own flex container with `flex:1;flex-wrap:wrap`, so
it wraps *inside itself* and Today stays on the right at every width. A flex
spacer in the shared row carried Today onto the second line on a phone.

On the Tracker, Today and Edit Sessions are grouped together on the right, so
the left side is just the date controls and the plan name.

### v18

- **Tapping a running parent channel opens its subcategory picker again.** It
  used to answer with the pause offer and nothing else, which made switching
  between two subcategories of the running parent impossible without stopping
  first. Both now happen: the picker opens and the pause toast rides above it.
  That works because `.toast` is z-index 60 and `.scrim` is 40, and the action
  toast is the one with `pointer-events:auto`. Pausing from it also closes the
  picker.
- **"Apply to today" is just "Apply"**, and the "From template: X / Changes
  here affect today only" preamble above it is gone. The grey/blue behaviour is
  unchanged: grey and disabled when today already matches the chosen template,
  blue the moment applying would change something.
- **Export Data Backup moved out of Settings** into the avatar menu, between
  Light mode and Settings. Settings keeps the other Data Management rows.

### Joy and Drain, v19

Proof that `CHANNEL_ATTRS` was worth building. Two new 1-5 schemes cost two
entries in that table; the channel editor's pickers, the Priorities sections,
`attrTotals()` and parent-to-subcategory inheritance all came for free, because
every one of them is generated from the table rather than written per scheme.

The only genuinely new code is a colour rule. The 1-5 ramp runs green to red,
which is right for drain and backwards for joy, so a scheme can now set
`invert:true` and `attrColor()` reads its ramp from the other end. Without it a
5 for joy would have been painted like a warning.

Beyond the table, only the explicit serialisers needed touching: `toRow()` /
`fromRow()` list channel columns by hand, and `OPTIONAL_COLUMNS.channels` gained
both names so the app works before the migration is run.

`supabase-channels-joy-drain-migration.sql` **was run on 2026-08-27**, so joy
and drain sync normally.

### First-run orientation, v20

`showIntroOnce()` puts one sheet in front of everyone - existing users as well
as new ones - saying the default channels are only a starting point and
pointing at the avatar menu.

The problem it solves: a new account lands on default channels that are not
theirs, with nothing on screen saying they can be changed, exactly when someone
is deciding whether the tool is for them.

- **Device-local** (`localStorage`, `dtt-intro-seen`), not a profile field. It
  records whether this person has read it; a profile field would sync the
  dismissal to a phone they have not opened yet. **If storage throws it counts
  as seen** - nagging every load is worse than never showing it.
- **The backdrop does not dismiss it.** Both buttons do, and both mark it seen.
  The point is that it gets read once.
- The pointer is a **small DOM mock of the top bar**, not a screenshot: it
  cannot go stale, it themes itself, and it sits next to real live chrome.
- Called at the end of `enterApp()`, inside a try/catch, so it can never break
  entry - `enterAppSafe()` would otherwise show the boot-error panel.

To show a new intro later, bump the key rather than reusing it.

### Attribute grouping, v21

Six schemes had become a flat stack in both places that show them, and it was
hard to see where one ended and the next began.

- **Priorities**: every scheme is now its own bordered card carrying its own
  hint, and the Eisenhower quadrant uses the same card, so the page reads as
  uniform blocks rather than one long list of bars.
- **Channel editor**: three cards - **Type of work** (Commitment, DRIP),
  **Priority** (Urgency, Importance), **Energy** (Joy, Drain). Membership is a
  `group` field on `CHANNEL_ATTRS`, so a new scheme joins a card by naming one
  and an unnamed scheme falls into "Other" rather than disappearing.

**`index.html` line endings are not uniform.** A multi-line anchor that looks
correct can fail to match while the same text matches with the other ending.
Any script editing this file should try CRLF and LF before giving up, or anchor
on single lines.

### All five Data Management actions were dead, v22

`exportDataBackup`, `checkDeletedDaysCount`, `restoreDeletedDays`,
`showDeleteRangePrompt` and `showCompleteResetConfirm` each called
`idbAll("day_notes","profile", ...)`. **`day_notes` has no `profile` index** -
it is keyed by date alone, which is the documented reason it does not sync - so
every one of those calls threw `The specified index was not found` and the
action did nothing. Long-standing; it only became visible because v20 promoted
Export backup to the avatar menu, where a silent failure would have been
obvious. They now read every note, which is correct: `day_notes` is not
profile-scoped in the first place.

**This is the landmine about missing indexes, in its quieter form.** The
documented version renders the whole app blank. This one killed five actions
behind buttons nobody presses often, silently, for an unknown length of time.
Worth running the sweep below after any change that touches storage.

A smoke pass over 22 views and transitions - every screen, both themes, day
navigation, zoom, all modals - now raises no errors, no unhandled rejections
and nothing on `console.error`.

### Two timers at once across devices, v23

Reported from a real iPad/iPhone pair, and reproduced exactly.

`startSessionOnChannel()` calls `stopRunning()` first, which ends only what
**this device** knows is running. So: the phone opens Admin and pushes it; the
iPad has not pulled yet, opens Marketing, and ends nothing. After the next sync
two rows carry `endTs: null`.

Both then accrue, because `updateTodayTotals()` counts any null-ended session
as `now() - startTs`. Only one tile shows the *Running* badge - `running` is a
single in-memory pointer - but two tiles count upward, which is what it looks
like from the outside. `reloadFromLocal()` made it permanent: it took the
**first** open session with `.find()` and never looked at the rest, so the
loser ran invisibly and forever.

`reconcileMultipleOpen()` runs on load and after every pull - a pull being
exactly when the other device's session arrives. The newest open session wins,
since it is what the person most recently chose, and each older one is closed
at the moment the next began: precisely what would have happened had both taps
landed on one device. Nothing is deleted and every time stays correctable in
the Day Editor. A toast says what happened rather than fixing it silently.

Verified: two-way and three-way pileups, identical start times producing no
negative durations, a single open session left untouched, and the load path.

**The underlying asymmetry is unchanged and is the thing to revisit** if this
recurs in another form: a device can only ever end sessions it knows about, so
any state that must be globally exclusive has this shape. Backlog 7.7 made the
same point about the merge rule.

### The day window belongs to the plan, v24

Start hour, end hour and slot size used to live in Settings, where they **did
nothing**: the handlers wrote to `planState` in memory, never persisted, never
re-rendered. Reloading reset them to the hardcoded 8/18/30. The markup also
existed twice with the same ids, so only the first copy was ever addressed.

They are now a property of a plan. `plans` and `dayplans` each carry
`startHour`, `endHour`, `increment`; a template holds its own window, a
materialised day inherits a copy, and "Save to template" carries it back.
Defaults are 8am-6pm in 30-minute slots, expressed as NULL in the database so
"unset" and "8" stay distinguishable.

`planWindow(rec)` resolves a record's window with defaults and guarantees
`endHour > startHour` so a grid can never come out empty.
`applyPlanWindow(rec)` writes it into `planState` - kept deliberately, because
every existing grid reader already reads `planState`, so each render just sets
it from the record it is about to draw and nothing downstream changed.

The controls sit on the Plan page and edit whatever is on screen: the selected
template, or today's materialised day. The Tracker calls
`applyPlanWindow(dayRec)` before drawing, so paging to a past day draws that
day's hours rather than whatever the Plan page last showed.

Verified: 8-18/30 gives 20 rows and 6-20/15 gives 56 on the same template; a
second template stays at the default; a day set to 7-11 hourly gives the
Tracker exactly four rows from 7:00 to 11:00.

`supabase-plan-window-migration.sql` **has not been run.** Until it does the
window works on-device but does not sync.

**A warning for anyone scripting edits to this file.** The long settings line
both closes a template literal and contains `getElementById("plannerStart")`.
A filter matching that substring deleted the whole line, and the resulting
syntax error was reported hundreds of lines away at `dedupChannels`. Match on
something anchored - `const plannerStart=` - and always re-run the parse check
in the browser after a scripted edit.

### Time format and Button size were dead controls, still in v24

Both Settings rows changed the visible `<select>`'s value and nothing else.
Cause: `initializeEventListeners()` runs once on `DOMContentLoaded`, and at
that moment it attached the `hourFmt`/`btnSize` change listeners to elements
inside a **dead, never-opened `#settingsScrim` block** that sat in the static
HTML. `openSettings()` builds the real, visible Settings page from scratch
every time via `stage.innerHTML=...`, producing brand-new `<select>` elements
with the same ids but *no listeners at all* - so selecting a new value updated
nothing. `checkDeletedDaysCount()`-style bugs from earlier in this session were
the same shape: a handler wired to the wrong copy of an element.

Fixed by wiring both selects for real inside `openSettings()`, next to the
other Data Management buttons that already lived there, and deleting the dead
`#settingsScrim` markup along with the two orphaned listeners.

**Removing that block cost a real regression, caught before it shipped:** the
first pass deleted only the block's *opening* `<div class="scrim" ...>` line,
not its full body. The remaining rows were left unwrapped from the scrim's
`display:none`, so "Export CSV" and a stray "Signed in as" row rendered as
plain, permanently-visible page content on every screen. A multi-line HTML
block must be deleted start-to-matching-end, never by matching its first line
alone - the fix here was to find the true closing `</div></div></div>` and
delete the whole span. Re-screenshotted every affected page afterward to
confirm nothing was left dangling.

Verified end-to-end, driven through the real UI (select a value, dispatch
`change`, close Settings, reload the whole app from IndexedDB): `hourFmt` and
`btnSize` both persist and take visible effect - dashboard tile height moved
172px -> 220px, and `fmtClock` output changed with the saved value, not just
the one passed manually.

### Plan-grid and Tracker labels now respect Time format

The Plan page's hour list and the Tracker's `renderAdheranceComparison()` both
built their row labels with hardcoded `h%12||12` / `"AM"/"PM"` math, ignoring
`state.profile.hourFmt` entirely - the actual cause of "I don't see military
time on the Plan page." A shared `fmtHourMin(h,m,fmt)` replaces both call
sites (and the Day window hour `<select>` options), mirroring `fmtClock`'s
12/24 rule without needing a `Date` - the grid's hour can be `24`, meaning the
far edge of the last slot, which a real Date object cannot represent cleanly.
`renderPlanSlots()` was left untouched: dead code, never called, same as the
duplicate `renderPlanSelect` noted below.

### Day window moved above the time grid, v24

It used to render after the grid, at the bottom of the page. It now sits
directly under "Editing template" / "Apply", before "Time blocks" - the
setting is chosen before it is used to draw anything below it.

### The top-left date now opens today's Day Editor, still v24

`#topDateBtn` was already a real button - it just reset the stage back to the
dashboard grid, which is nearly always where you already are. Repurposed as
the fast path into the Day Editor, now that it is used daily rather than
occasionally: one tap, from anywhere in the app, straight to today.

The date text itself is untouched - still `8/29` on a phone, the long ordinal
form on desktop - Mark asked to keep it exactly as it is. A small pencil-in-a-
square SVG sits beside it, matching the outline-icon style the bottom nav
already uses, so the button reads as a button rather than a label. The avatar
menu's "Edit a day" is unchanged and still works, as a second route to the
same screen.

**The desktop date string still reads "August 29rd."** The ordinal-suffix
logic (`['st','nd','rd'][((d.getDate()%10)-1)%3]||'th'`) mishandles every date
ending in 9 - 9th, 19th, 29th all come out wrong. Spotted, not fixed: Mark did
not confirm he wanted it touched, and he was explicit about not changing the
date's format in this pass.

### Per-session notes, still v24

A quick tag on one block - a name, a topic - not the whole-day reflection
`day_notes` already holds. Deliberately not on the Plan page: a plan slot is a
recurring template, and a note like "who was that with" belongs to one actual
instance of it, which is a session, not a slot. Deliberately not on the
Summary page either, on request - written where it is reviewed, not
duplicated where it would just add clutter.

- **Lives on the session record** (`sessions.note`), synced like every other
  session field. `OPTIONAL_COLUMNS.sessions=["note"]` so the app degrades
  gracefully before the migration runs, same pattern as every other optional
  column this session added.
- **A single-line input, `maxlength=60`, in the block sheet** - opened by
  tapping any block in the Day Editor timeline. Deliberately not a textarea:
  the field itself should read as "quick tag," not "journal entry," before
  anyone starts typing. Saves on `change` (blur), matching the existing
  `day_notes` textarea convention.
- **The sheet stays open after saving.** Only closes on an actual decision -
  reassigning a channel, splitting, deleting. `blockScrim` lives outside
  `#dayEditorBody`, so calling `afterDayEdit()` to refresh the timeline
  underneath does not touch or close what is still open on top of it.
- **A small two-line "note" mark** appears on a timeline block that carries
  one, distinct from the dot already used for "Running" elsewhere so the two
  cannot be confused. Verified it appears the moment a note saves and
  disappears the moment one is cleared.

`supabase-sessions-note-migration.sql` **has not been run.** Until it does,
notes are stored and shown on the device but do not sync. The column is
capped at 60 characters server-side too, matching the input, rather than left
unbounded.

### The top-date edit icon gets a border, still v24

A plain pencil read as decoration more than as a button. A small bordered
square around just the icon - not the date text, which Mark asked to leave
alone - reads as an icon button on its own, the way the rest of the app's
controls do.

### Day Editor: two columns, notes inline, still v24

`buildTimeline()` now returns a grid of two siblings sharing one clock: the
existing `#tlWrap` timeline unchanged on the left (`1.5fr`), a `note` input per
block on the right (`1fr`), each positioned with the same `tlY()` math as its
block so the rows line up exactly. Editing a note no longer requires opening
the block sheet - type in the row, blur, saved. The sheet still has its own
note field too; both write the same `sessions.note`.

Same `h>=24` cutoff the block label already uses gates whether a row gets an
input at all - below that a 16px input has nowhere to go without swallowing
the next row, and 16px is non-negotiable on iOS (Landmines: text inputs zoom
the page below that). Zoom in for notes on a crowded block, same answer as
everywhere else on this screen.

### Week view, first attempt, still v24

New avatar menu item, "Week", under "Edit a day". `openWeekEditor(dk)` /
`renderWeekEditor()` follow the same entry/re-render split as the Tracker,
with the same re-entry guard (recapturing the stage on every week change
would make Home close this page back into itself).

Modelled on the Tracker's grid, widened to seven days: a time rail plus one
column per weekday (Monday start, matching the Summary's existing Week
Overview), Actual only - there is no plan to compare a week against, so
Planned/Match do not apply. The hour range is derived from what the week
actually held (min/max across all its sessions), same idea as the Day
Editor's own rail, not a fixed clock. A cell with a note shows the channel
chip and the note **stacked underneath it**, not beside it - side by side in
an 84px column left room for neither; first draft, caught in a screenshot
before committing.

`openWeekView()`/`closeWeekView()` above are unrelated, older, unreferenced
dead code (a card layout, not a grid). Named this feature differently on
purpose so nothing here can shadow or be shadowed by it.

Not yet done: no editing on this page (read-only, matching "let's see how it
looks" framing) and increment is a fixed 30 minutes, not the per-plan window
work from earlier this session.

### Week view: bigger type, and a Window control, still v24

Every size in the first pass was too small (9-11px, 34px rows) - bumped
across the board (12-16px, 44px rows), re-verified the note-under-chip stack
still clips cleanly at the new sizes rather than just eyeballing it.

Added a Window control - Starts / Ends / Slot - above the grid, matching the
Day window control already on the Plan page. `loadWeekWindow()` /
`saveWeekWindow()` persist it in `localStorage` (`dtt-week-window`), because
this is a device preference ("I only want 8-6," "give me the full day"), not
data tied to any one week. Unset, the grid still auto-fits the week's own
data exactly as before; the first change to any of the three selects switches
it to an explicit, persisted window from then on.

### Summary consolidated into a Stats page, and Priorities folded in, still v24

Mark's own framing: "have it all in one place." Three surfaces that had
grown up separately - Summary, the standalone Priorities page, and a
Dashboard modal that turned out to be **fully dead code** - are now one page.

- **The Dashboard modal (`openDashboard`/`renderDashboard`/`dashScrim`) had
  zero callers anywhere in the app.** Not hidden, not hard to find - genuinely
  unreachable. Its Plan vs Actual card also read `dayplans.blocks`, a shape
  the data model has not used all session (`dayplans.schedule` everywhere
  else) - reviving it as-is would have shipped something broken. Its Insights,
  Time-by-channel and two chart functions (`dailyTrendChart`, `hourChart`)
  were sound, though, and are what the new Stats page's day/week/month/year/
  all-tabbed content is built from.
- **Priorities** (`openPriorities`/`renderPriorities`, its own avatar menu
  item) is retired as a standalone destination. `attrTotals()`, `QUADRANTS`
  and the CHANNEL_ATTRS-driven cards are folded into the same page, reading
  the *same* range tabs as the channel-time stats above them - one tab row
  drives everything now, instead of Priorities keeping its own.
- **New: an Adherence card**, matched blocks and budget credited/planned,
  aggregated across whichever range is selected. This is what Summary's old
  ad-hoc "Time Lookback" section (This Week/This Month/Last Quarter/Custom,
  with its own adherence total) was reaching for; that section and its bespoke
  preset buttons are gone, superseded by reusing the one shared tab row.
- **Retired**: the "Today's Summary" rate-today card (redundant with the Day
  Editor's own rating UI) and the Week Overview cards / Day-by-Day Breakdown
  table (redundant with the Week view's new per-day journal strip, below).
- **Kept, at the very bottom, per explicit instruction**: Complete History
  Log. "I don't know if we need it... let's put it at the bottom and reassess
  once we have the new information in front of us."
- **Export CSV lost its only entry point** when `dashScrim` was removed - it
  was reachable exclusively through the dead Dashboard modal, so in practice
  it was unreachable too. Moved to the avatar menu, beside Export backup.
- Bottom-nav label and page header: **Summary -> Stats**.

**A near-miss worth remembering.** The first deletion pass assumed
`openDashboard()`/`renderDashboard()` were the entire span between two
anchors and deleted everything in between. `saveDayRatingAndNotes()`,
`starCellHtml()`, `dayTypeSelectHtml()` and `window.setDayTypeFromSummary`
were sitting interleaved in that span, unrelated to the dead modal, and got
swallowed with it. `saveDayRatingAndNotes()` is load-bearing everywhere a
star or a note gets saved - the Day Editor's own rating UI included - so this
would have broken rating a day anywhere in the app, not just on this page.
Caught by the same sweep-every-screen verification this project leans on
throughout, restored verbatim from git history, then the sweep re-run clean.
**Deleting "from function A to function B" is only safe once every top-level
declaration in that span has been listed and confirmed unrelated - never
assumed from the two endpoints alone.**

### Week view: a day-by-day journal strip, still v24

Below the grid and totals, one card per day - day type, star rating, Timing/
Budget adherence, and notes - the same fields the Stats page's History Log
shows, but scoped to the seven days already on screen and reusing the exact
same `starCellHtml()`/`dayTypeSelectHtml()`/`adhCellHtml()`/
`saveDayRatingAndNotes()` as everywhere else. Editable in place: rate a day,
change its type, or click into its notes, right from the week grid.

`dayTypeSelectHtml()`'s `<select>` always wires its `onchange` to
`window.setDayTypeFromSummary`, which unconditionally re-renders the Stats
page - correct there, wrong here. `openWeekEditor()`/`renderWeekEditor()`
**overwrite that global with a week-scoped version** while the page is open,
so a day-type change on the Week view re-renders the Week view instead of
silently doing nothing, or rendering the wrong screen underneath this one.
Any future page reusing `dayTypeSelectHtml()` needs the same override.

### Bottom nav: Edit a day and Week promoted out of the avatar menu, still v24

Mark's read: with Edit a day and Week now used daily, burying them one tap
deeper in the avatar menu didn't match how often they're reached for. The
bottombar stays at exactly four buttons - the fourth is no longer a fourth
destination but a **More** overflow (`•••`) opening a small popup anchored
above the bar, holding the three lower-frequency destinations.

- Direct: **Dashboard, Edit a day, Week**
- Behind **More**: **Plan, Tracker, Stats**

`btnEditDay` calls `openDayEditor(todayKey())`, `btnWeek` calls
`openWeekEditor(todayKey())` - same destinations the avatar menu used to
open, so no new code path, just a shorter one. The avatar menu's "Edit a
day"/"Week" rows were removed since they'd now just duplicate the bottombar.

The More popup is a `#moreMenu` div (`position:fixed`, anchored bottom-right
above the bar) toggled the same way `#avatarMenu` is - `stopPropagation` on
the button, a document-level click closes it, each row closes it before
running its action. Its rows are built by `moreMenuItem()`, a small twin of
`avatarMenuItem()` that closes `#moreMenu` instead of `#avatarMenu` -
kept separate rather than parameterizing the existing helper's container,
so the avatar menu (used everywhere else) stays untouched.

This split is explicitly a first pass ("let's try your way until we come up
with [something better]") - expect the Plan/Tracker/Stats vs. direct-button
grouping to get revisited once real usage is in.

### Perfect Week: all 7 weekday templates side by side, still v24

Mark wanted to see Monday through Sunday's templates next to each other and
edit them in place, rather than one at a time through the Templates
dropdown. New third tab on the Plan page, next to Today and Templates.

**The weekday-plan link is now a real field, not a name match.**
`weekdayTemplate()` (used to decide what a real future day materialises
from) has matched a plan named e.g. "monday" to Mondays since before this
feature existed - convenient, but renaming that plan silently detached it
with no error. `plans` gets a new nullable `assignedWeekday` (0-6,
`Date.getDay()` convention) instead. `loadPlans()` runs a one-time,
idempotent backfill (`backfillAssignedWeekdays()`) that sets the field from
the old name match wherever nothing already claims that day, so every
existing user's Monday-Friday templates come out assigned with no action
needed. `weekdayTemplate()` still falls back to the name match after that,
for the narrow window before a given profile has been through the backfill.

**One plan per weekday, one weekday per plan** - `assignWeekdayToPlan()`
clears whichever plan currently holds a day before handing it to the new
one, so two plans never claim the same day. Not a DB constraint (a unique
index would fight the app mid-sync across devices) - enforced entirely in
app code, documented in `supabase-plans-assigned-weekday-migration.sql`.

**Shared time axis, not seven independent grids.** Each plan still keeps
its own start/end/increment for the Templates tab. Perfect Week draws all
7 columns on one common window instead - `weekViewWindow()` - so a click
lands on the same clock time in every column. That window is a view
setting on the profile (`state.profile.weekViewWindow`), not written onto
any plan, and does not sync to Supabase (profiles' `toRow`/`fromRow` were
not extended for it) - a deliberate simplification, since it is a per-
device display preference, not data. If asked "why doesn't my Plan-page
window follow me to my phone," this is why.

Editing a column writes straight to that weekday's `plan.schedule` - same
data the Templates tab shows, so a change here is visible there and vice
versa. Column header is a `<select>`: pick an existing template (reassigning
it here, away from wherever it was), "+ New template" (creates one named
after the day, already assigned), or "— unassign —". An unassigned day
renders no grid, just a prompt, rather than a blank set of slots that would
look editable but silently do nothing.

`openWeekSlotModal()`/`setWeekSlot()`/`planWeekDrop()`/`weekSlotAttrs()` are
small twins of the existing `openPlanSlotModal()`/`setPlanSlot()`/
`planDrop()`/`slotAttrs()` - Perfect Week can have several different plans
open on screen at once, where the originals always target whichever single
record Today/Templates mode currently has active, so threading a target
through the shared functions risked the single-day editor over a feature
that did not need to touch it.

### Bottombar, second pass: Dashboard / Plan / Tracker / More, still v24

Mark's follow-up once Edit a day and Week had been living in the bar for a
bit: Edit a day was redundant with the top-left date/pencil shortcut (which
already opens today's Day Editor in one tap), and Plan/Tracker turned out
to be the two reached for daily beyond that shortcut - not Week.

- Bottombar: **Dashboard, Plan, Tracker, More** - Edit a day dropped
  entirely, not even into More; the top-left shortcut already covers it.
- More: **Week, Stats, Channels**. Channels moved out of the avatar menu -
  it is a page you navigate to and edit (your category list), the same
  kind of thing Week/Stats/Plan/Tracker are, not an account-level action.
  The avatar menu is now account/utility only: theme toggle, Settings,
  Sign out, sync status. (Export backup/CSV moved again shortly after -
  see the Import backup section below - so this list is smaller still.)

**Regression caught and fixed in the same pass:** a leftover delegated
`document` click listener from before Edit a day/Week/More existed still
matched `e.target.id==="btnAdhere"` and called `openPlanAdherence()` - dead
code the moment the very first bottombar refactor removed that id from the
bar, silently reactivated the moment this pass put `id="btnAdhere"` back.
Tracker was firing `openPlanAdherence()` twice per tap. Fixed by dropping
that one clause; the delegated listener still handles `setForTodayBtn`/
`addPlanBtn`/`deletePlanBtn`, which are genuinely dynamic (recreated by
every `renderPlanPageUI()` innerHTML write, so a direct listener would not
survive a re-render) - unlike `btnAdhere`, which is a permanent bottombar
element and needs exactly one, direct listener. Caught by the same
scripted click-count sweep this session has used throughout, not by eye -
a second/third view of the same double-fire would have looked identical
on screen; only counting the calls exposed it. Worth remembering next time
an old id gets reintroduced into a live element: grep for every reference
to that id before assuming a fresh `addEventListener` is the only wiring.

### Import backup, and Backup moves into Settings, still v24

Export backup existed with no way to load the file back in. Mark asked for
the import side, and separately asked whether Export backup/CSV belonged
under Settings rather than in the avatar menu once there would be three of
them. Both landed together: **Backup** is now its own section in Settings
(Export CSV, Export backup, Import backup), above Data Management; the
avatar menu lost both export rows and is down to theme, Settings, sign out,
sync status.

**Import merges into the profile you already have open - it does not
create a separate restored one.** The obvious design would restore into a
fresh profile and leave the original untouched, but this app hides
multiple profiles rather than exposing a switcher (see "Profiles are
hidden, not removed" in `renderAvatarMenu()`) - a second profile created by
import would be reachable by nobody, ever. A restore nobody can see is not
a restore. Merging avoids that trap and is just as safe a different way:
channels are matched by name and reused rather than duplicated, and
sessions/day notes are only ever ADDED, never replacing or deleting a
record already there.

**Plans and dayplans (templates) are deliberately left out of the import,
though the export still captures them.** Your current templates are live
and in use; restoring old ones back over them risked changing something
you did not touch, for a lower-value win than the sessions themselves -
templates are regenerable by hand, a day of tracked time is not. The
backup file is still a complete historical record if a template ever
needs to be manually rebuilt from it.

Backup format bumped to `formatVersion: 2` - v1 only captured profile,
sessions, and day notes, so restoring one landed every session on a
channel that no longer existed anywhere ("(deleted)" everywhere). v2 adds
channels, plans, and dayplans to the export. `importDataBackup()` still
accepts a v1 file (no `formatVersion` field) - it just cannot rebuild
channels that were never captured, and says so in the confirm prompt
before importing.

Verified: all 3 script blocks parse; a seeded round-trip (export a test
profile's channels+sessions, re-import that same file into itself) landed
exactly as designed - sessions doubled (additive, expected), channels held
steady at the same count (matched by name, not duplicated); an unreadable
file and a validly-shaped-but-wrong JSON file each surfaced the right toast
and changed nothing; all three new Settings buttons and the trimmed avatar
menu wired correctly - zero console/window errors throughout.

---

*Written 2026-08-26 by Claude (Opus 5) after the v1–v3 session.*
*Updated 2026-08-27: v12 Day Editor timeline, and the deploy-status
correction at the top.*
