-- ヤンキース 希望入力
-- スタッフの任意メモ機能
-- Supabase > SQL Editor で、このファイル全体を1回実行してください。

alter table public.night_availability
  add column if not exists memo text;


create or replace function public.set_shift_memo_with_pin(
  p_staff_id uuid,
  p_work_date date,
  p_memo text,
  p_pin text
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $func$
declare
  v_memo text := nullif(btrim(coalesce(p_memo, '')), '');
begin
  if not public.verify_staff_pin(p_staff_id, p_pin) then
    raise exception '暗証番号が違います。';
  end if;

  if p_work_date is null then
    raise exception '日付を選択してください。';
  end if;

  if timezone('Asia/Tokyo', now()) >=
     (
       date_trunc('month', p_work_date::timestamp)
       - interval '1 month'
       + interval '23 days'
     ) then
    raise exception 'この月の希望入力は締め切りました。締切は前月23日23:59です。';
  end if;

  if char_length(coalesce(v_memo, '')) > 100 then
    raise exception 'メモは100文字以内で入力してください。';
  end if;

  update public.night_availability
  set memo = v_memo
  where staff_id = p_staff_id
    and work_date = p_work_date;

  if not found then
    raise exception '先に希望を登録してください。';
  end if;

  return jsonb_build_object(
    'ok', true,
    'staff_id', p_staff_id,
    'work_date', p_work_date
  );
end;
$func$;


create or replace function public.get_admin_shift_schedule_with_memo(
  p_start_date date,
  p_end_date date
)
returns table (
  work_date date,
  staff_id uuid,
  staff_name text,
  shift_pattern text,
  memo text
)
language plpgsql
security definer
set search_path = public
as $func$
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  return query
  select
    n.work_date,
    s.id,
    s.name,
    n.shift_pattern,
    n.memo
  from public.night_availability n
  join public.staffs s
    on s.id = n.staff_id
  where n.work_date between p_start_date and p_end_date
  order by n.work_date, s.name;
end;
$func$;


create or replace function public.admin_set_shift_memo(
  p_staff_id uuid,
  p_work_date date,
  p_memo text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_memo text := nullif(btrim(coalesce(p_memo, '')), '');
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  if char_length(coalesce(v_memo, '')) > 100 then
    raise exception 'メモは100文字以内で入力してください。';
  end if;

  update public.night_availability
  set memo = v_memo
  where staff_id = p_staff_id
    and work_date = p_work_date;

  if not found then
    raise exception '対象の登録が見つかりません。';
  end if;

  return jsonb_build_object('ok', true);
end;
$func$;


revoke all on function public.set_shift_memo_with_pin(uuid,date,text,text) from public;
revoke all on function public.get_admin_shift_schedule_with_memo(date,date) from public;
revoke all on function public.admin_set_shift_memo(uuid,date,text) from public;

grant execute on function public.set_shift_memo_with_pin(uuid,date,text,text)
to anon, authenticated;

grant execute on function public.get_admin_shift_schedule_with_memo(date,date)
to authenticated;

grant execute on function public.admin_set_shift_memo(uuid,date,text)
to authenticated;
