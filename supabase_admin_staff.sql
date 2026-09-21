-- ヤンキース 夜勤希望
-- 管理者画面「職員管理」用RPC
-- Supabase > SQL Editor で、このファイル全体を1回だけ実行してください。

create or replace function public.admin_list_staffs()
returns table (
  id uuid,
  name text,
  active boolean
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  return query
  select s.id, s.name, s.active
  from public.staffs s
  order by s.active desc, s.name;
end;
$$;

create or replace function public.admin_add_staff(p_name text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
  v_id uuid;
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  if v_name = '' then
    raise exception '職員名を入力してください。';
  end if;

  if char_length(v_name) > 50 then
    raise exception '職員名は50文字以内にしてください。';
  end if;

  select s.id
    into v_id
  from public.staffs s
  where s.name = v_name
  limit 1;

  if v_id is not null then
    if exists (
      select 1
      from public.staffs s
      where s.id = v_id
        and s.active = true
    ) then
      raise exception '同じ名前の職員がすでに登録されています。';
    end if;

    update public.staffs
    set active = true
    where id = v_id;

    return jsonb_build_object(
      'ok', true,
      'id', v_id,
      'restored', true
    );
  end if;

  insert into public.staffs (name, active)
  values (v_name, true)
  returning id into v_id;

  return jsonb_build_object(
    'ok', true,
    'id', v_id,
    'restored', false
  );
end;
$$;

create or replace function public.admin_rename_staff(
  p_staff_id uuid,
  p_name text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_name text := btrim(coalesce(p_name, ''));
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  if v_name = '' then
    raise exception '職員名を入力してください。';
  end if;

  if char_length(v_name) > 50 then
    raise exception '職員名は50文字以内にしてください。';
  end if;

  update public.staffs
  set name = v_name
  where id = p_staff_id;

  if not found then
    raise exception '対象の職員が見つかりません。';
  end if;

  return jsonb_build_object('ok', true);
exception
  when unique_violation then
    raise exception '同じ名前の職員がすでに登録されています。';
end;
$$;

create or replace function public.admin_delete_staff(
  p_staff_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $func$
declare
  v_name text;
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  select s.name into v_name
  from public.staffs s
  where s.id = p_staff_id;

  if v_name is null then
    raise exception '対象の職員が見つかりません。';
  end if;

  delete from public.night_availability
  where staff_id = p_staff_id;

  delete from public.staffs
  where id = p_staff_id;

  return jsonb_build_object(
    'ok', true,
    'name', v_name
  );
end;
$func$;

create or replace function public.admin_set_staff_active(
  p_staff_id uuid,
  p_active boolean
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.jwt() ->> 'email', '') <> 'admin@example.com' then
    raise exception '管理者としてログインしてください。';
  end if;

  update public.staffs
  set active = p_active
  where id = p_staff_id;

  if not found then
    raise exception '対象の職員が見つかりません。';
  end if;

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_list_staffs() from public;
revoke all on function public.admin_add_staff(text) from public;
revoke all on function public.admin_rename_staff(uuid, text) from public;
revoke all on function public.admin_delete_staff(uuid) from public;
revoke all on function public.admin_set_staff_active(uuid, boolean) from public;

grant execute on function public.admin_list_staffs() to authenticated;
grant execute on function public.admin_add_staff(text) to authenticated;
grant execute on function public.admin_rename_staff(uuid, text) to authenticated;
grant execute on function public.admin_delete_staff(uuid) to authenticated;
grant execute on function public.admin_set_staff_active(uuid, boolean) to authenticated;
