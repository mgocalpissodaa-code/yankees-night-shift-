
-- セントラル シフト希望入力（試作）
-- Supabase SQL Editor でこのファイル全体を1回実行してください。

create extension if not exists pgcrypto;

create table if not exists public.central_staffs (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.central_request_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  symbol text not null,
  color text not null default '#2563eb',
  active boolean not null default true,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

create table if not exists public.central_shift_requests (
  id uuid primary key default gen_random_uuid(),
  staff_id uuid not null references public.central_staffs(id) on delete cascade,
  work_date date not null,
  request_type_id uuid not null references public.central_request_types(id),
  note text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint central_shift_requests_staff_date_key unique (staff_id, work_date)
);

alter table public.central_staffs enable row level security;
alter table public.central_request_types enable row level security;
alter table public.central_shift_requests enable row level security;

revoke all on table public.central_staffs from anon, authenticated;
revoke all on table public.central_request_types from anon, authenticated;
revoke all on table public.central_shift_requests from anon, authenticated;

insert into public.central_staffs(name) values
  ('米山'),('安庭'),('田上'),('小松'),('南'),('馬場'),('松本'),('森'),
  ('有村'),('宮路'),('上原み'),('丸田'),('小松た'),('小島'),('今吉'),
  ('上口'),('堀之内')
on conflict (name) do nothing;

insert into public.central_request_types(name, symbol, color, sort_order) values
  ('休み希望', '◎', '#ef4444', 10),
  ('有給', '有', '#7c3aed', 20),
  ('早出希望', '早', '#d97706', 30),
  ('遅出希望', '遅', '#2563eb', 40),
  ('7時出勤希望', '7時', '#059669', 50),
  ('その他・勤務条件', '他', '#64748b', 60)
on conflict (name) do update set
  symbol = excluded.symbol,
  color = excluded.color,
  sort_order = excluded.sort_order;

create or replace function public.central_get_active_staffs()
returns table(id uuid, name text)
language sql
security definer
set search_path = public
as $func$
  select s.id, s.name
  from public.central_staffs s
  where s.active = true
  order by s.created_at, s.name;
$func$;

create or replace function public.central_get_request_types()
returns table(id uuid, name text, symbol text, color text, sort_order integer)
language sql
security definer
set search_path = public
as $func$
  select t.id, t.name, t.symbol, t.color, t.sort_order
  from public.central_request_types t
  where t.active = true
  order by t.sort_order, t.name;
$func$;

create or replace function public.central_get_shift_requests(
  p_start_date date,
  p_end_date date
)
returns table(
  work_date date,
  staff_id uuid,
  staff_name text,
  request_type_id uuid,
  request_type_name text,
  request_symbol text,
  request_color text,
  note text
)
language sql
security definer
set search_path = public
as $func$
  select
    r.work_date,
    s.id as staff_id,
    s.name as staff_name,
    t.id as request_type_id,
    t.name as request_type_name,
    t.symbol as request_symbol,
    t.color as request_color,
    coalesce(r.note, '') as note
  from public.central_shift_requests r
  join public.central_staffs s on s.id = r.staff_id
  join public.central_request_types t on t.id = r.request_type_id
  where r.work_date between p_start_date and p_end_date
  order by r.work_date, s.created_at, s.name;
$func$;

create or replace function public.central_set_shift_request(
  p_staff_id uuid,
  p_work_date date,
  p_request_type_id uuid,
  p_note text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $func$
begin
  if p_work_date < (now() at time zone 'Asia/Tokyo')::date then
    raise exception '過去の日付には登録できません';
  end if;

  if not exists (
    select 1 from public.central_staffs
    where id = p_staff_id and active = true
  ) then
    raise exception '職員が見つかりません';
  end if;

  if not exists (
    select 1 from public.central_request_types
    where id = p_request_type_id and active = true
  ) then
    raise exception '希望区分が見つかりません';
  end if;

  insert into public.central_shift_requests(
    staff_id, work_date, request_type_id, note, updated_at
  )
  values (
    p_staff_id,
    p_work_date,
    p_request_type_id,
    nullif(btrim(coalesce(p_note, '')), ''),
    now()
  )
  on conflict (staff_id, work_date)
  do update set
    request_type_id = excluded.request_type_id,
    note = excluded.note,
    updated_at = now();
end;
$func$;

create or replace function public.central_cancel_shift_request(
  p_staff_id uuid,
  p_work_date date
)
returns void
language plpgsql
security definer
set search_path = public
as $func$
begin
  if p_work_date < (now() at time zone 'Asia/Tokyo')::date then
    raise exception '過去の日付は取り消せません';
  end if;

  delete from public.central_shift_requests
  where staff_id = p_staff_id
    and work_date = p_work_date;
end;
$func$;

create or replace function public.central_admin_list_staffs()
returns table(id uuid, name text, active boolean, created_at timestamptz)
language plpgsql
security definer
set search_path = public
as $func$
begin
  if coalesce(auth.jwt()->>'email', '') <> 'admin@example.com' then
    raise exception '管理者権限がありません';
  end if;

  return query
  select s.id, s.name, s.active, s.created_at
  from public.central_staffs s
  order by s.active desc, s.created_at, s.name;
end;
$func$;

create or replace function public.central_admin_add_staff(p_name text)
returns uuid
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_id uuid;
  v_name text := btrim(coalesce(p_name, ''));
begin
  if coalesce(auth.jwt()->>'email', '') <> 'admin@example.com' then
    raise exception '管理者権限がありません';
  end if;

  if v_name = '' then
    raise exception '名前を入力してください';
  end if;

  insert into public.central_staffs(name, active)
  values (v_name, true)
  returning id into v_id;

  return v_id;
exception
  when unique_violation then
    raise exception '同じ名前の職員が登録されています';
end;
$func$;

create or replace function public.central_admin_rename_staff(
  p_staff_id uuid,
  p_name text
)
returns void
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_name text := btrim(coalesce(p_name, ''));
begin
  if coalesce(auth.jwt()->>'email', '') <> 'admin@example.com' then
    raise exception '管理者権限がありません';
  end if;

  if v_name = '' then
    raise exception '名前を入力してください';
  end if;

  update public.central_staffs
  set name = v_name
  where id = p_staff_id;

  if not found then
    raise exception '職員が見つかりません';
  end if;
exception
  when unique_violation then
    raise exception '同じ名前の職員が登録されています';
end;
$func$;

create or replace function public.central_admin_delete_staff(
  p_staff_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $func$
begin
  if coalesce(auth.jwt()->>'email', '') <> 'admin@example.com' then
    raise exception '管理者権限がありません';
  end if;

  delete from public.central_staffs
  where id = p_staff_id;

  if not found then
    raise exception '職員が見つかりません';
  end if;
end;
$func$;

revoke all on function public.central_get_active_staffs() from public;
revoke all on function public.central_get_request_types() from public;
revoke all on function public.central_get_shift_requests(date,date) from public;
revoke all on function public.central_set_shift_request(uuid,date,uuid,text) from public;
revoke all on function public.central_cancel_shift_request(uuid,date) from public;
revoke all on function public.central_admin_list_staffs() from public;
revoke all on function public.central_admin_add_staff(text) from public;
revoke all on function public.central_admin_rename_staff(uuid,text) from public;
revoke all on function public.central_admin_delete_staff(uuid) from public;

grant execute on function public.central_get_active_staffs() to anon, authenticated;
grant execute on function public.central_get_request_types() to anon, authenticated;
grant execute on function public.central_get_shift_requests(date,date) to anon, authenticated;
grant execute on function public.central_set_shift_request(uuid,date,uuid,text) to anon, authenticated;
grant execute on function public.central_cancel_shift_request(uuid,date) to anon, authenticated;

grant execute on function public.central_admin_list_staffs() to authenticated;
grant execute on function public.central_admin_add_staff(text) to authenticated;
grant execute on function public.central_admin_rename_staff(uuid,text) to authenticated;
grant execute on function public.central_admin_delete_staff(uuid) to authenticated;
