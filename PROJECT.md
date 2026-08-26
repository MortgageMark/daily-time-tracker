# Time Tracker — Project Handoff

**Read this first if you are a new chat session picking up this project.**
It replaces the older `PROJECT_DOCUMENTATION.md`, which contained stale paths
and leaked credentials. Do not trust that file.

- **Live:** https://dailytimetracker.com
- **Current release:** v3 (`17919e2`), deployed 2026-08-26
- **Status:** stable, in daily use

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
apple-touch-icon.png            180px, iOS home screen
icon-192.png / icon-512.png     manifest icons (512 doubles as maskable)
favicon-32.png                  browser tab
.gitignore                      ignores version.json and scratch files
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

A `daily-time-tracker` entry already exists in `.claude/launch.json` (in the
parent `Claude Folder`). Start it through the preview tooling rather than a
raw shell.

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
| Dialogs | `uiConfirm`, `uiPrompt`, `uiDialog` |
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
- iOS caches the home screen icon and name at install. Changing them requires
  removing and re-adding the shortcut, once.
- Supabase's built-in mailer is rate-limited to a few messages an hour and often
  lands in spam. Fine for testing, needs real SMTP before onboarding users.
- No timezone handling for sessions crossing midnight.
- `ensureObjectStores()` is dead code that would recreate stores without
  indexes. Never called. Delete it if you are ever cleaning up.

---

## 7. Backlog

Mark's ideas, captured 2026-08-26. **Not yet started.** When he asks
"what's next", these are the options.

### 7.1 Backfill and retroactive editing — *highest practical value*
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

### 7.3 Must / Will / Want tiers
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

### 7.4 Urgent / Important scoring → Eisenhower quadrant
Rate each channel 1–5 on **urgency** and 1–5 on **importance**, then plot time
spent across the four Eisenhower quadrants. The coaching value is seeing how
much time lands in "urgent but not important."

Two integer fields per channel plus a quadrant visualisation. Composes
naturally with Must/Will/Want — likely the same editor screen.

### 7.5 DRIP categorisation
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

### Suggested order

1. **Backfill** — most immediate daily value, self-contained, scoring already supports it
2. **Must/Will/Want** — small change, large reporting payoff
3. **Urgent/Important + DRIP** — same generic mechanism, build once
4. **Perfect Week** — needs a scoping conversation first
5. **Coach access** — needs a security design session

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

---

*Written 2026-08-26 by Claude (Opus 5) after the v1–v3 session.*
