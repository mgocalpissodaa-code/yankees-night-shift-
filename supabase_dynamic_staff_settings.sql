-- ヤンキース 希望入力
-- 職員ごとの「勤務設定」を管理画面から変更できるようにする追加SQL
-- Supabase > SQL Editor でこのファイル全体を1回実行してください。

create table if not exists public.staff_shift_settings (
  staff_id uuid primary key references public.staffs(id) on delete cascade,
  input_mode text not null default 'none'
    check (input_mode in ('none','off','work')),
  allow_paid boolean not null default false,
  allow_public_rest boolean not null default false,
  shift_options jsonb not null default '[]'::jsonb,
  updated_at timestamptz not null default now()
);

alter table public.staff_shift_settings enable row level security;
revoke all on table public.staff_shift_settings from anon, authenticated;

-- 現在のヤンキース職員設定を初期登録。
-- 既に設定済みの職員は上書きしません。
insert into public.staff_shift_settings (
  staff_id,
  input_mode,
  allow_paid,
  allow_public_rest,
  shift_options
)
select
  s.id,
  case replace(replace(s.name,' ',''),'　','')
    when '藤井亮輔' then 'off'
    when '桑原莉子' then 'off'
    when '古垣竜也' then 'off'
    when '内藤昌子' then 'work'
    when '前川良司' then 'work'
    when '鹿島佑斗' then 'work'
    when '鎌田フサ子' then 'work'
    else 'none'
  end,
  case
    when replace(replace(s.name,' ',''),'　','') in
      ('藤井亮輔','桑原莉子','古垣竜也','内藤昌子','前川良司','鹿島佑斗','鎌田フサ子')
    then true else false
  end,
  case
    when replace(replace(s.name,' ',''),'　','') = '鎌田フサ子'
    then true else false
  end,
  case replace(replace(s.name,' ',''),'　','')
    when '内藤昌子' then
      '[{"value":"22:00-03:00","start":"22:00","end":"03:00","next_day":true}]'::jsonb
    when '前川良司' then
      '[{"value":"22:00-06:00","start":"22:00","end":"06:00","next_day":true}]'::jsonb
    when '鹿島佑斗' then
      '[{"value":"22:00-06:00","start":"22:00","end":"06:00","next_day":true}]'::jsonb
    when '鎌田フサ子' then
      '[
        {"value":"22:00-06:00","start":"22:00","end":"06:00","next_day":true},
        {"value":"07:00-06:00","start":"07:00","end":"06:00","next_day":true},
        {"value":"07:00-10:00","start":"07:00","end":"10:00","next_day":false}
      ]'::jsonb
    else '[]'::jsonb
  end
from public.staffs s
on conflict (staff_id) do nothing;


create or replace function public.get_staff_shift_settings()
returns table (
  staff_id uuid,
  staff_name text,
  input_mode text,
  allow_paid boolean,
  allow_public_rest boolean,
  shift_options jsonb
)
language sql
security definer
set search_path = public
as $func$
  select
    s.id,
    cfg.input_mode,
    cfg.allow_paid,
    cfg.allow_public_rest,
    cfg.shift_options
  from public.staffs s
  join public.staff_shift_settings cfg
    on cfg.staff_id = s.id
  where s.active = true
    and cfg.input_mode <> 'none'
  order by s.name;
$func$;


create or replace function public.admin_list_staff_shift_settings()
returns table (
  staff_id uuid,
  input_mode text,
  allow_paid boolean,
  allow_public_rest boolean,
  shift_options jsonb
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
    s.id,
    s.name,
    coalesce(cfg.input_mode,'none') as input_mode,
    coalesce(cfg.allow_paid,false) as allow_paid,
    coalesce(cfg.allow_public_rest,false) as allow_public_rest,
    coalesce(cfg.shift_options,'[]'::jsonb) as shift_options
  from public.staffs s
  left join public.staff_shift_settings cfg
    on cfg.staff_id = s.id
  order by s.active desc, s.name;
end;
$func$;


create or replace function public.admin_set_staff_shift_settings(
  p_staff_id uuid,
  p_input_mode text,
  p_allow_paid boolean,
  p_allow_public_rest boolean,
  p_shift_options jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_options jsonb := coalesce(p_shift_options,'[]'::jsonb);
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  if p_input_mode not in ('none','off','work') then
    raise exception '入力方法を選び直してください。';
  end if;

  if jsonb_typeof(v_options) <> 'array' then
    raise exception '勤務時間の設定を確認してください。';
  end if;

  if exists (
    select 1
    from jsonb_array_elements(v_options) x
    where coalesce(x->>'value','') = ''
       or coalesce(x->>'start','') !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
       or coalesce(x->>'end','') !~ '^(?:[01][0-9]|2[0-3]):[0-5][0-9]$'
       or jsonb_typeof(x->'next_day') <> 'boolean'
  ) then
    raise exception '勤務時間は開始・終了時刻と翌日設定を確認してください。';
  end if;

  if p_input_mode <> 'work' then
    v_options := '[]'::jsonb;
  end if;

  insert into public.staff_shift_settings (
    staff_id,
    input_mode,
    allow_paid,
    allow_public_rest,
    shift_options,
    updated_at
  )
  values (
    p_staff_id,
    p_input_mode,
    coalesce(p_allow_paid,false),
    coalesce(p_allow_public_rest,false),
    v_options,
    now()
  )
  on conflict (staff_id)
  do update set
    input_mode = excluded.input_mode,
    allow_paid = excluded.allow_paid,
    allow_public_rest = excluded.allow_public_rest,
    shift_options = excluded.shift_options,
    updated_at = now();

  return jsonb_build_object('ok',true,'staff_id',p_staff_id);
end;
$func$;


-- 登録時の勤務パターン判定を、職員ごとの勤務設定から確認する。
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
  v_active boolean;
  v_mode text;
  v_allow_paid boolean;
  v_allow_public_rest boolean;
  v_options jsonb;
  v_allowed boolean := false;
begin
  if p_work_date is null then
    raise exception '日付を選択してください。';
  end if;

  if p_work_date < (timezone('Asia/Tokyo', now()))::date then
    raise exception '過去の日付には登録できません。';
  end if;

  -- 職員画面は前月23日23:59まで。管理者は締切後も変更可能。
  if coalesce(auth.jwt() ->> 'email','') <> 'admin@example.com'
     and timezone('Asia/Tokyo', now()) >=
       (date_trunc('month', p_work_date::timestamp)
        - interval '1 month'
        + interval '23 days') then
    raise exception 'この月の希望入力は締め切りました。締切は前月23日23:59です。';
  end if;

  select
    s.active,
    cfg.input_mode,
    cfg.allow_paid,
    cfg.allow_public_rest,
    cfg.shift_options
  into
    v_active,
    v_mode,
    v_allow_paid,
    v_allow_public_rest,
    v_options
  from public.staffs s
  left join public.staff_shift_settings cfg
    on cfg.staff_id = s.id
  where s.id = p_staff_id;

  if coalesce(v_active,false) = false then
    raise exception '対象の職員が見つかりません。';
  end if;

  if coalesce(v_mode,'none') = 'none' then
    raise exception 'この職員はWeb入力なしに設定されています。';
  end if;

  if p_shift_pattern = 'PAID' and coalesce(v_allow_paid,false) then
    v_allowed := true;
  elsif p_shift_pattern = 'PUBLIC_REST' and coalesce(v_allow_public_rest,false) then
    v_allowed := true;
  elsif p_shift_pattern = 'OFF' and v_mode = 'off' then
    v_allowed := true;
  elsif v_mode = 'work' and exists (
    select 1
    from jsonb_array_elements(coalesce(v_options,'[]'::jsonb)) x
    where x->>'value' = p_shift_pattern
  ) then
    v_allowed := true;
  end if;

  if not v_allowed then
    raise exception 'この職員の勤務設定では選択できない内容です。';
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


revoke all on function public.get_staff_shift_settings() from public;
revoke all on function public.admin_list_staff_shift_settings() from public;
revoke all on function public.admin_set_staff_shift_settings(uuid,text,boolean,boolean,jsonb) from public;

grant execute on function public.get_staff_shift_settings()
to anon, authenticated;

grant execute on function public.admin_list_staff_shift_settings()
to authenticated;

grant execute on function public.admin_set_staff_shift_settings(uuid,text,boolean,boolean,jsonb)
to authenticated;

-- 暗証番号経由の登録は引き続き利用。
revoke execute on function public.register_shift_request(uuid,date,text) from anon;
grant execute on function public.register_shift_request(uuid,date,text) to authenticated;
