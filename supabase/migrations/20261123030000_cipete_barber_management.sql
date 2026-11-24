create sequence if not exists public.barber_code_seq;

alter table public.barbers
  add column if not exists barber_code text;

update public.barbers
set barber_code = 'BR-' || lpad(nextval('public.barber_code_seq')::text, 3, '0')
where barber_code is null;

alter table public.barbers
  alter column barber_code set not null;

create unique index if not exists barbers_barber_code_uidx
  on public.barbers (barber_code);

create unique index if not exists barbers_branch_display_name_uidx
  on public.barbers (branch_id, lower(display_name));

revoke all on sequence public.barber_code_seq from public, anon, authenticated;

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
  if coalesce((select public.current_app_role())::text, '') not in ('owner', 'admin_cashier') then
    raise exception 'Akses hanya untuk owner atau admin';
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
  if coalesce((select public.current_app_role())::text, '') not in ('owner', 'admin_cashier') then
    raise exception 'Akses hanya untuk owner atau admin';
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
  if coalesce((select public.current_app_role())::text, '') not in ('owner', 'admin_cashier') then
    raise exception 'Akses hanya untuk owner atau admin';
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

create or replace view public.active_barber_catalog
with (security_barrier = true)
as
select b.id, b.display_name
from public.barbers b
join public.branches br on br.id = b.branch_id
where b.is_active = true
  and br.slug = 'cipete'
  and br.is_active = true;

revoke all on public.active_barber_catalog from public;
grant select on public.active_barber_catalog to anon, authenticated;
