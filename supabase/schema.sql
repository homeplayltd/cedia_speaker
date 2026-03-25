-- ================================================================
-- CEDIA Board Speaker Queue — Supabase Schema
-- Run this entire file in your Supabase SQL Editor
-- ================================================================

-- Meeting state (single row, always id = 1)
create table if not exists meeting_state (
  id integer primary key default 1,
  topic text not null default '',
  current_speaker_name text default null,
  current_speaker_subject text default null,
  speaker_started_at timestamptz default null,
  updated_at timestamptz default now(),
  constraint single_row check (id = 1)
);

-- Seed the single row
insert into meeting_state (id) values (1) on conflict (id) do nothing;

-- Speaker queue (FIFO by joined_at)
create table if not exists queue (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  subject text not null,
  joined_at timestamptz default now()
);

-- ----------------------------------------------------------------
-- Enable Realtime
-- ----------------------------------------------------------------
alter publication supabase_realtime add table meeting_state;
alter publication supabase_realtime add table queue;

-- ----------------------------------------------------------------
-- Row Level Security (open for this use-case — tighten if needed)
-- ----------------------------------------------------------------
alter table meeting_state enable row level security;
alter table queue enable row level security;

create policy "Public read/write on meeting_state"
  on meeting_state for all to anon
  using (true)
  with check (true);

create policy "Public read/write on queue"
  on queue for all to anon
  using (true)
  with check (true);

-- ----------------------------------------------------------------
-- RPC: clear_queue
-- Deletes all rows from the queue with SECURITY DEFINER so it
-- bypasses RLS. Called from the moderator panel.
-- ----------------------------------------------------------------
create or replace function clear_queue()
returns void
language sql
security definer
as $$
  delete from queue where true;
$$;

-- Grant execute to anon role
grant execute on function clear_queue() to anon;

-- ----------------------------------------------------------------
-- RPC: reset_meeting
-- Clears the queue AND resets meeting_state in one call.
-- ----------------------------------------------------------------
create or replace function reset_meeting()
returns void
language sql
security definer
as $$
  delete from queue where true;
  update meeting_state set
    topic = '',
    current_speaker_name = null,
    current_speaker_subject = null,
    speaker_started_at = null,
    updated_at = now()
  where id = 1;
$$;

grant execute on function reset_meeting() to anon;

-- ----------------------------------------------------------------
-- RPC: set_topic
-- Sets a new topic and clears the queue atomically.
-- ----------------------------------------------------------------
create or replace function set_topic(new_topic text)
returns void
language sql
security definer
as $$
  delete from queue where true;
  update meeting_state set
    topic = new_topic,
    current_speaker_name = null,
    current_speaker_subject = null,
    speaker_started_at = null,
    updated_at = now()
  where id = 1;
$$;

grant execute on function set_topic(text) to anon;

-- ----------------------------------------------------------------
-- RPC: next_speaker  
-- Removes first queue entry and sets them as current speaker.
-- ----------------------------------------------------------------
create or replace function next_speaker()
returns void
language plpgsql
security definer
as $$
declare
  v_next record;
begin
  select * into v_next from queue order by joined_at asc limit 1;
  if v_next is null then return; end if;
  delete from queue where id = v_next.id;
  update meeting_state set
    current_speaker_name = v_next.name,
    current_speaker_subject = v_next.subject,
    speaker_started_at = now(),
    updated_at = now()
  where id = 1;
end;
$$;

grant execute on function next_speaker() to anon;

-- ----------------------------------------------------------------
-- RPC: end_speaker
-- Clears the current speaker without advancing.
-- ----------------------------------------------------------------
create or replace function end_speaker()
returns void
language sql
security definer
as $$
  update meeting_state set
    current_speaker_name = null,
    current_speaker_subject = null,
    speaker_started_at = null,
    updated_at = now()
  where id = 1;
$$;

grant execute on function end_speaker() to anon;

-- ----------------------------------------------------------------
-- RPC: remove_from_queue
-- Removes a single speaker by UUID.
-- ----------------------------------------------------------------
create or replace function remove_from_queue(row_id uuid)
returns void
language sql
security definer
as $$
  delete from queue where id = row_id;
$$;

grant execute on function remove_from_queue(uuid) to anon;
