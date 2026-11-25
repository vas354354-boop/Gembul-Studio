create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role
  from public.profiles p
  where p.id = (select auth.uid())
    and p.is_active = true
$$;

create or replace function public.current_user_is_active_staff()
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.profiles p
    where p.id = (select auth.uid())
      and p.is_active = true
      and p.role in ('owner', 'admin_cashier')
  )
$$;

revoke all on function public.current_user_is_active_staff() from public, anon;
grant execute on function public.current_user_is_active_staff() to authenticated;

create or replace function public.admin_dashboard_metrics(
  p_start timestamptz,
  p_end timestamptz,
  p_queue_date date
)
returns table (
  revenue numeric,
  completed_transactions bigint,
  bookings bigint,
  waiting_queue bigint,
  new_customers bigint,
  active_cipete_barbers bigint,
  active_members bigint
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (select public.current_user_is_active_staff()) then
    raise exception 'Akses hanya untuk owner atau admin staf';
  end if;

  if p_start is null
    or p_end is null
    or p_queue_date is null
    or p_end <= p_start
    or p_end - p_start > interval '1 day' then
    raise exception 'Rentang ringkasan tidak valid';
  end if;

  return query
  select
    coalesce((
      select sum(t.total)
      from public.transactions t
      where t.status = 'completed'
        and t.created_at >= p_start
        and t.created_at < p_end
    ), 0)::numeric,
    (
      select count(*)
      from public.transactions t
      where t.status = 'completed'
        and t.created_at >= p_start
        and t.created_at < p_end
    )::bigint,
    (
      select count(*)
      from public.bookings b
      where b.starts_at >= p_start
        and b.starts_at < p_end
    )::bigint,
    (
      select count(*)
      from public.queues q
      where q.queue_date = p_queue_date
        and q.status = 'waiting'
    )::bigint,
    (
      select count(*)
      from public.customers c
      where c.created_at >= p_start
        and c.created_at < p_end
    )::bigint,
    (
      select count(*)
      from public.barbers b
      join public.branches br on br.id = b.branch_id
      where b.is_active = true
        and br.slug = 'cipete'
        and br.is_active = true
    )::bigint,
    (
      select count(*)
      from public.memberships m
      where m.status = 'active'
    )::bigint;
end;
$$;

revoke all on function public.admin_dashboard_metrics(timestamptz, timestamptz, date) from public, anon;
grant execute on function public.admin_dashboard_metrics(timestamptz, timestamptz, date) to authenticated;

create or replace function public.manageable_cipete_barbers()
returns table (
  id uuid,
  barber_code text,
  display_name text,
  is_active boolean
)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (select public.current_user_is_active_staff()) then
    raise exception 'Akses hanya untuk owner atau admin staf aktif';
  end if;

  return query
  select b.id, b.barber_code, b.display_name, b.is_active
  from public.barbers b
  join public.branches br on br.id = b.branch_id
  where br.slug = 'cipete'
  order by b.is_active desc, b.display_name;
end;
$$;

create or replace function public.add_cipete_barber(p_display_name text)
returns table (
  id uuid,
  barber_code text,
  display_name text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch_id uuid;
  v_display_name text;
begin
  if not (select public.current_user_is_active_staff()) then
    raise exception 'Akses hanya untuk owner atau admin staf aktif';
  end if;

  v_display_name := trim(regexp_replace(coalesce(p_display_name, ''), '\s+', ' ', 'g'));
  if char_length(v_display_name) < 2 or char_length(v_display_name) > 60 then
    raise exception 'Nama profesional harus 2 sampai 60 karakter';
  end if;
  if lower(v_display_name) in ('cab cipete', 'barber cipete', 'barber', 'admin', 'owner') then
    raise exception 'Masukkan nama profesional barber, bukan nama cabang atau jabatan';
  end if;

  select br.id into v_branch_id
  from public.branches br
  where br.slug = 'cipete' and br.is_active = true;
  if v_branch_id is null then
    raise exception 'Cabang Cipete tidak ditemukan atau tidak aktif';
  end if;

  return query
  insert into public.barbers as new_barber (branch_id, barber_code, display_name, is_active)
  values (
    v_branch_id,
    'BR-' || lpad(nextval('public.barber_code_seq')::text, 3, '0'),
    v_display_name,
    true
  )
  returning new_barber.id, new_barber.barber_code, new_barber.display_name;
exception
  when unique_violation then
    raise exception 'Nama profesional tersebut sudah terdaftar untuk Cipete';
end;
$$;

create or replace function public.set_cipete_barber_active(
  p_barber_id uuid,
  p_is_active boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch_id uuid;
begin
  if not (select public.current_user_is_active_staff()) then
    raise exception 'Akses hanya untuk owner atau admin staf aktif';
  end if;

  select br.id into v_branch_id
  from public.branches br
  where br.slug = 'cipete' and br.is_active = true;

  update public.barbers
  set is_active = p_is_active,
      updated_at = now()
  where id = p_barber_id
    and branch_id = v_branch_id;
  return found;
end;
$$;

revoke all on function public.manageable_cipete_barbers() from public, anon;
revoke all on function public.add_cipete_barber(text) from public, anon;
revoke all on function public.set_cipete_barber_active(uuid, boolean) from public, anon;
grant execute on function public.manageable_cipete_barbers() to authenticated;
grant execute on function public.add_cipete_barber(text) to authenticated;
grant execute on function public.set_cipete_barber_active(uuid, boolean) to authenticated;
