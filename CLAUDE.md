# CLAUDE.md — Daily Time Tracker

**Read `PROJECT.md` first.** It is the authoritative handoff document for this
project — architecture, deploy pipeline, database, and conventions all live
there. Do not start work without reading it.

## Quick orientation

- **Live:** https://dailytimetracker.com
- **The whole app is one file:** `index.html` (~425 KB, all CSS and JS inline)
- **No build step, no framework.** Netlify's build command only stamps a version.
- **Host:** Netlify, auto-deploys from `master`
- **Database:** Supabase

## Local preview

A launch config is defined in `.claude/launch.json`. Start it with the
preview tool (server name `daily-time-tracker`, port 8888) — do not run a
dev server through Bash.

## Ignore this file

`../daily-time-tracker-docs/PROJECT_DOCUMENTATION.md` is **stale** and contains
leaked credentials. `PROJECT.md` replaced it. Do not trust or copy from it.

## Conventions

- Never paste tokens or keys into files or chat.
- Because the app is a single large file, always read the surrounding region
  before editing — grep for the function name, then read that block.
