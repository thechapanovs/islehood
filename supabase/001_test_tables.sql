-- A table the Unity app can read, to prove the connection works
create table public.hello (
  id bigint generated always as identity primary key,
  message text not null,
  created_at timestamptz not null default now()
);

alter table public.hello enable row level security;

-- Security rule: anyone can read hello rows, nobody can change them from the app
create policy "anyone can read hello"
  on public.hello for select
  to anon, authenticated
  using (true);

insert into public.hello (message) values ('Hello from Supabase!');

-- A table only the Python service writes to, to prove the schedule works
create table public.heartbeat (
  id bigint generated always as identity primary key,
  ran_at timestamptz not null default now()
);

alter table public.heartbeat enable row level security;
-- No policies on purpose: the app can't read or write it. Only the secret key can.
