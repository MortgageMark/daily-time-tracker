-- Channel attributes: Must/Will/Want, DRIP, and the two Eisenhower axes.
--
-- Run this once in the Supabase SQL editor (Dashboard > SQL Editor > New query
-- > paste > Run) for project vybypyeyzfgakenkotbw.
--
-- The app does NOT need this to work. Until it runs, the four fields save and
-- work normally on the device but do not sync: Supabase rejects an upsert that
-- names a column it does not have, so the app detects that once, pushes the
-- channel without these fields, and retries the full set every 10 minutes.
-- Running this migration therefore starts syncing them without a reload and
-- without anything to undo.
--
-- Safe to run more than once: every statement is IF NOT EXISTS.

alter table public.channels add column if not exists tier        text;
alter table public.channels add column if not exists drip        text;
alter table public.channels add column if not exists urgency     smallint;
alter table public.channels add column if not exists importance  smallint;

-- Value guards. The app only ever writes these values, but the database
-- should not depend on the client being correct.
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'channels_tier_check') then
    alter table public.channels
      add constraint channels_tier_check
      check (tier is null or tier in ('must','will','want'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'channels_drip_check') then
    alter table public.channels
      add constraint channels_drip_check
      check (drip is null or drip in ('D','R','I','P'));
  end if;

  if not exists (select 1 from pg_constraint where conname = 'channels_urgency_check') then
    alter table public.channels
      add constraint channels_urgency_check
      check (urgency is null or urgency between 1 and 5);
  end if;

  if not exists (select 1 from pg_constraint where conname = 'channels_importance_check') then
    alter table public.channels
      add constraint channels_importance_check
      check (importance is null or importance between 1 and 5);
  end if;
end $$;

-- No RLS changes are needed. These are new columns on an existing table, so
-- the existing owner = auth.uid() policies on public.channels already cover
-- them. Nothing here widens access.

-- Force PostgREST to pick the new columns up immediately rather than waiting
-- for its schema cache to expire.
notify pgrst, 'reload schema';
