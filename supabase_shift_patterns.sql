-- ヤンキース 希望入力：勤務パターン対応
-- Supabase > SQL Editor で、このファイル全体を1回だけ実行してください。

alter table public.night_availability
  add column if not exists shift_pattern text;

-- これまでの夜勤希望データがあれば、現在の勤務時間を補完
update public.night_availability n
set shift_pattern =
  case replace(replace(s.name, ' ', ''), '　', '')
    when '内藤昌子' then '22:00-03:00'
    when '前川良司' then '22:00-06:00'
    when '鹿島佑斗' then '22:00-06:00'
    when '鎌田フサ子' then '22:00-06:00'
    else n.shift_pattern
  end
from public.staffs s
where s.id = n.staff_id
  and n.shift_pattern is null;

create or replace function public.register_shift_request(
  p_staff_id uuid,
  p_work_date date,
  p_shift_pattern text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_name text;
begin
  if p_work_date is null then
    raise exception '日付を選択してください。';
  end if;

  if p_work_date < current_date then
    raise exception '過去の日付には登録できません。';
  end if;

  select replace(replace(s.name, ' ', ''), '　', '')
    into v_name
  from public.staffs s
  where s.id = p_staff_id
    and s.active = true;

  if v_name is null then
    raise exception '対象の職員が見つかりません。';
  end if;

  if v_name in ('藤井亮輔', '桑原莉子', '古垣竜也') then
    if p_shift_pattern not in ('OFF', 'PAID') then
      raise exception 'この職員は休み希望または有給を登録してください。';
    end if;

  elsif v_name = '内藤昌子' then
    if p_shift_pattern not in ('22:00-03:00', 'PAID') then
      raise exception '内藤さんは22:00〜翌3:00または有給で登録してください。';
    end if;

  elsif v_name in ('前川良司', '鹿島佑斗') then
    if p_shift_pattern not in ('22:00-06:00', 'PAID') then
      raise exception 'この職員は22:00〜翌6:00または有給で登録してください。';
    end if;

  elsif v_name = '鎌田フサ子' then
    if p_shift_pattern not in ('22:00-06:00', '07:00-06:00', '07:00-10:00', 'PUBLIC_REST', 'PAID') then
      raise exception '鎌田さんの勤務時間・公休・有給を選び直してください。';
    end if;

  else
    raise exception 'この職員はヤンキースの希望入力対象外です。';
  end if;

  insert into public.night_availability (
    staff_id,
    work_date,
    shift_pattern
  )
  values (
    p_staff_id,
    p_work_date,
    p_shift_pattern
  )
  on conflict (staff_id, work_date)
  do update
    set shift_pattern = excluded.shift_pattern;

  return jsonb_build_object(
    'ok', true,
    'staff_id', p_staff_id,
    'work_date', p_work_date,
    'shift_pattern', p_shift_pattern
  );
end;
$func$;

create or replace function public.get_shift_schedule(
  p_start_date date,
  p_end_date date
)
returns table (
  work_date date,
  staff_id uuid,
  staff_name text,
  shift_pattern text
)
language sql
security definer
set search_path = public
as $func$
  select
    n.work_date,
    s.id as staff_id,
    s.name as staff_name,
    n.shift_pattern
  from public.night_availability n
  join public.staffs s
    on s.id = n.staff_id
  where n.work_date between p_start_date and p_end_date
  order by n.work_date, s.name;
$func$;

create or replace function public.admin_cancel_shift_request(
  p_staff_id uuid,
  p_work_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_deleted integer;
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  delete from public.night_availability
  where staff_id = p_staff_id
    and work_date = p_work_date;

  get diagnostics v_deleted = row_count;

  if v_deleted = 0 then
    raise exception '対象の登録が見つかりません。';
  end if;

  return jsonb_build_object(
    'ok', true,
    'staff_id', p_staff_id,
    'work_date', p_work_date
  );
end;
$func$;

create or replace function public.admin_bulk_cancel_shift_requests(
  p_staff_id uuid,
  p_work_dates date[]
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_deleted integer;
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  if p_staff_id is null or p_work_dates is null or array_length(p_work_dates, 1) is null then
    raise exception '職員と日付を選択してください。';
  end if;

  delete from public.night_availability
  where staff_id = p_staff_id
    and work_date = any(p_work_dates);

  get diagnostics v_deleted = row_count;

  return jsonb_build_object(
    'ok', true,
    'deleted', v_deleted,
    'staff_id', p_staff_id
  );
end;
$func$;

revoke all on function public.register_shift_request(uuid, date, text) from public;
revoke all on function public.get_shift_schedule(date, date) from public;
revoke all on function public.admin_cancel_shift_request(uuid, date) from public;
revoke all on function public.admin_bulk_cancel_shift_requests(uuid, date[]) from public;

grant execute on function public.register_shift_request(uuid, date, text) to anon, authenticated;
grant execute on function public.get_shift_schedule(date, date) to anon, authenticated;
grant execute on function public.admin_cancel_shift_request(uuid, date) to authenticated;
grant execute on function public.admin_bulk_cancel_shift_requests(uuid, date[]) to authenticated;
