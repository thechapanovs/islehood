-- TEST ONLY: lets the app read heartbeat rows (read only). Remove when the heartbeat job is removed.
grant select on public.heartbeat to anon, authenticated;

create policy "Test only: anyone can read heartbeat"
  on public.heartbeat
  for select
  to anon, authenticated
  using (true);
