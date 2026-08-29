-- Per-session note: adds sessions.note.
--
-- Run once in the Supabase SQL editor (Dashboard > SQL Editor > New query >
-- paste > Run), in project vybypyeyzfgakenkotbw.
--
-- IMPORTANT: check the project ref in your browser's address bar first.
-- Running this in the wrong project fails with "relation public.sessions
-- does not exist", which looks alarming but means nothing was changed.
--
-- The app does NOT need this to work. Until it runs, notes are stored and
-- shown on the device but do not sync. Supabase rejects an upsert naming a
-- column it does not have, so the app detects that once, pushes sessions
-- without this field, and retries the full set every 10 minutes -- meaning
-- running this starts the sync with no reload and nothing to undo.
--
-- 60 characters client-side (the app's input has maxlength=60) - this is
-- deliberately a quick tag, not a paragraph, so the column is sized to match
-- rather than left unbounded.
--
-- Safe to run more than once.

alter table public.sessions add column if not exists note text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'sessions_note_length_check') then
    alter table public.sessions
      add constraint sessions_note_length_check check (note is null or char_length(note) <= 60);
  end if;
end $$;

-- No RLS changes needed. This is a new column on an existing table, so the
-- existing owner = auth.uid() policy already covers it.

notify pgrst, 'reload schema';

-- Verify: should return one row, note / text.
select column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and table_name   = 'sessions'
  and column_name  = 'note';
