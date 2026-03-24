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
