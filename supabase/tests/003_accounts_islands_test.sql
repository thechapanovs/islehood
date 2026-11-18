-- Tests for 003_accounts_islands.sql. Run from the repo root with:
--   psql "$URL" -X -f supabase/tests/003_accounts_islands_test.sql
-- Everything is rolled back at the end, so no test users are left behind.
-- Lines marked EXPECT say what you should see. Errors marked "permission denied" are good.

begin;

insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data) values
 ('11111111-1111-1111-1111-111111111111','00000000-0000-0000-0000-000000000000','authenticated','authenticated','ann@example.test','{"display_name":"Ann","time_zone":"America/Chicago"}'),
 ('22222222-2222-2222-2222-222222222222','00000000-0000-0000-0000-000000000000','authenticated','authenticated','bo@example.test','{}');

\echo '1. EXPECT 2 rows: Ann (America/Chicago) and bo (UTC), each with a solo island, an 8-character code, creator, active'
select u.display_name, u.time_zone, i.name, i.is_solo, length(i.invite_code) as code_len, m.role, m.status
from public.users u join public.memberships m on m.user_id = u.id join public.islands i on i.id = m.island_id
order by u.display_name;

set local role authenticated;
select set_config('request.jwt.claims','{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}',true) \gset

\echo '2. EXPECT 1, 1, 1 (Ann sees only herself)'
select (select count(*) from public.users) users, (select count(*) from public.islands) islands, (select count(*) from public.memberships) memberships;

\echo '3. EXPECT UPDATE 0 (cannot edit Bo)'
update public.users set display_name = 'Hacked' where id = '22222222-2222-2222-2222-222222222222';

\echo '4. EXPECT one row: Ann B, America/Denver (can edit herself)'
update public.users set display_name = 'Ann B', time_zone = 'America/Denver'
where id = '11111111-1111-1111-1111-111111111111' returning display_name, time_zone;

\echo '5. EXPECT permission denied (locked column)'
savepoint a;
update public.users set created_at = now() where id = '11111111-1111-1111-1111-111111111111';
rollback to a;

\echo '6. EXPECT permission denied (cannot insert islands)'
savepoint b;
insert into public.islands (name, created_by) values ('x','11111111-1111-1111-1111-111111111111');
rollback to b;

\echo '7. EXPECT permission denied (cannot insert memberships)'
savepoint c;
insert into public.memberships (island_id, user_id)
  select id, '11111111-1111-1111-1111-111111111111' from public.islands limit 1;
rollback to c;

\echo '8. EXPECT permission denied (cannot delete islands)'
savepoint d;
delete from public.islands;
rollback to d;

reset role;
set local role anon;
\echo '9. EXPECT permission denied (anonymous cannot read users)'
savepoint e;
select count(*) from public.users;
rollback to e;

reset role;
rollback;

\echo '10. EXPECT 0 and 0 (nothing left behind)'
select (select count(*) from auth.users where email like '%@example.test') as leftover_test_users,
       (select count(*) from public.users) as leftover_users;
