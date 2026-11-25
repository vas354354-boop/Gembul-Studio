create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  address text not null,
  maps_url text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.branches (slug, name, address, maps_url)
values (
  'cipete',
  'GEMBUL Studio Cipete',
  'Jl. Bunga Mawar No. 22, RT. 2/RW. 2, Cipete Selatan, Cilandak, Jakarta Selatan 12410',
  'https://maps.app.goo.gl/1kCfFAB22MmhvFUc7'
)
on conflict (slug) do update
set name = excluded.name,
    address = excluded.address,
    maps_url = excluded.maps_url,
    is_active = true,
    updated_at = now();

alter table public.branches enable row level security;

alter table public.barbers
  add column if not exists branch_id uuid references public.branches(id);

update public.barbers
set branch_id = (select id from public.branches where slug = 'cipete')
where branch_id is null;

alter table public.barbers
  alter column branch_id set not null;

create index if not exists barbers_branch_active_idx
  on public.barbers (branch_id, display_name)
  where is_active = true;

alter table public.bookings
  add column if not exists branch_id uuid references public.branches(id);

update public.bookings
set branch_id = (select id from public.branches where slug = 'cipete')
where branch_id is null;

alter table public.bookings
  alter column branch_id set not null;

create index if not exists bookings_branch_starts_at_idx
  on public.bookings (branch_id, starts_at);

alter table public.queues
  add column if not exists branch_id uuid references public.branches(id);

update public.queues q
set branch_id = coalesce(
  (select b.branch_id from public.bookings b where b.id = q.booking_id),
  (select id from public.branches where slug = 'cipete')
)
where q.branch_id is null;

alter table public.queues
  alter column branch_id set not null;

create index if not exists queues_branch_date_idx
  on public.queues (branch_id, queue_date);

create or replace view public.active_barber_catalog
with (security_barrier = true)
as
select b.id, b.display_name
from public.barbers b
join public.branches br on br.id = b.branch_id
where b.is_active = true
  and br.slug = 'cipete'
  and br.is_active = true;

revoke all on public.barbers from anon, authenticated;
revoke select (id, display_name) on public.barbers from anon, authenticated;
revoke all on public.active_barber_catalog from public;
grant select on public.active_barber_catalog to anon, authenticated;

create or replace function public.create_customer_booking(
  p_service_ids uuid[],
  p_barber_id uuid,
  p_starts_at timestamptz,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer public.customers%rowtype;
  v_branch_id uuid;
  v_service_count integer;
  v_booking_id uuid;
  v_queue_id uuid;
  v_queue_number integer;
  v_queue_date date;
  v_duration integer;
begin
  select * into v_customer
  from public.customers
  where profile_id = auth.uid();

  if v_customer.id is null then
    raise exception 'Profil pelanggan belum tersedia';
  end if;

  select id into v_branch_id
  from public.branches
  where slug = 'cipete' and is_active = true;

  if v_branch_id is null then
    raise exception 'Lokasi booking Cipete sedang tidak tersedia';
  end if;

  if p_service_ids is null or cardinality(p_service_ids) = 0 then
    raise exception 'Pilih minimal satu layanan';
  end if;

  if p_starts_at <= now() then
    raise exception 'Waktu booking harus di masa depan';
  end if;

  select count(distinct s.id)
  into v_service_count
  from public.services s
  where s.id = any(p_service_ids)
    and s.is_active = true;

  if v_service_count <> cardinality(p_service_ids) then
    raise exception 'Ada layanan yang tidak aktif atau tidak ditemukan';
  end if;

  if not exists (
    select 1
    from public.barbers b
    where b.id = p_barber_id
      and b.branch_id = v_branch_id
      and b.is_active = true
  ) then
    raise exception 'Barber Cipete tidak tersedia';
  end if;

  select coalesce(sum(s.duration_minutes), 0)
  into v_duration
  from public.services s
  where s.id = any(p_service_ids);

  perform pg_advisory_xact_lock(hashtext(p_barber_id::text), 0);

  if exists (
    select 1
    from public.bookings b
    where b.barber_id = p_barber_id
      and b.status not in ('cancelled', 'no_show')
      and p_starts_at < b.starts_at + make_interval(mins => coalesce((
        select sum(s.duration_minutes)::integer
        from public.booking_services bs
        join public.services s on s.id = bs.service_id
        where bs.booking_id = b.id
      ), 45))
      and p_starts_at + make_interval(mins => v_duration) > b.starts_at
  ) then
    raise exception 'Waktu tersebut bertabrakan dengan booking lain';
  end if;

  insert into public.bookings (customer_id, barber_id, branch_id, starts_at, status, notes)
  values (
    v_customer.id,
    p_barber_id,
    v_branch_id,
    p_starts_at,
    'confirmed',
    left(coalesce(p_notes, ''), 500)
  )
  returning id into v_booking_id;

  insert into public.booking_services (booking_id, service_id, unit_price)
  select v_booking_id, s.id, s.price
  from public.services s
  where s.id = any(p_service_ids)
  on conflict (booking_id, service_id) do update
  set unit_price = excluded.unit_price;

  v_queue_date := (p_starts_at at time zone 'Asia/Jakarta')::date;
  perform pg_advisory_xact_lock(hashtext(v_branch_id::text), hashtext(v_queue_date::text));

  select coalesce(max(queue_number), 0) + 1
  into v_queue_number
  from public.queues
  where branch_id = v_branch_id
    and queue_date = v_queue_date;

  insert into public.queues (
    branch_id,
    queue_date,
    queue_number,
    customer_id,
    booking_id,
    barber_id,
    status
  ) values (
    v_branch_id,
    v_queue_date,
    v_queue_number,
    v_customer.id,
    v_booking_id,
    p_barber_id,
    'waiting'
  )
  returning id into v_queue_id;

  return jsonb_build_object(
    'booking_id', v_booking_id,
    'queue_id', v_queue_id,
    'queue_number', v_queue_number,
    'queue_date', v_queue_date,
    'starts_at', p_starts_at,
    'branch', 'Cipete'
  );
end;
$$;

revoke all on function public.create_customer_booking(uuid[], uuid, timestamptz, text) from public, anon;
grant execute on function public.create_customer_booking(uuid[], uuid, timestamptz, text) to authenticated;
