create table if not exists public.branch_business_hours (
  branch_id uuid not null references public.branches(id) on delete cascade,
  day_of_week smallint not null check (day_of_week between 0 and 6),
  opens_at time not null,
  closes_at time not null,
  is_open boolean not null default true,
  primary key (branch_id, day_of_week),
  check (closes_at > opens_at)
);

insert into public.branch_business_hours (branch_id, day_of_week, opens_at, closes_at, is_open)
select b.id, day_number, time '09:00', time '22:00', true
from public.branches b
cross join generate_series(0, 6) as day_number
where b.slug = 'cipete'
on conflict (branch_id, day_of_week) do update
set opens_at = excluded.opens_at,
    closes_at = excluded.closes_at,
    is_open = excluded.is_open;

alter table public.branch_business_hours enable row level security;
revoke all on public.branch_business_hours from public, anon, authenticated;

create or replace function public.validate_booking_business_hours()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_day smallint;
  v_start_time time;
  v_hours public.branch_business_hours%rowtype;
begin
  v_day := extract(dow from (new.starts_at at time zone 'Asia/Jakarta'))::smallint;
  v_start_time := (new.starts_at at time zone 'Asia/Jakarta')::time;

  select * into v_hours
  from public.branch_business_hours h
  where h.branch_id = new.branch_id
    and h.day_of_week = v_day;

  if not found or not v_hours.is_open then
    raise exception 'Cabang Cipete tutup pada hari yang dipilih';
  end if;

  if v_start_time < v_hours.opens_at or v_start_time >= v_hours.closes_at then
    raise exception 'Jam booking Cipete adalah % sampai % WIB', v_hours.opens_at, v_hours.closes_at;
  end if;

  return new;
end;
$$;

create or replace function public.validate_booking_service_fits_hours()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_booking public.bookings%rowtype;
  v_day smallint;
  v_hours public.branch_business_hours%rowtype;
  v_total_duration integer;
  v_finish_time time;
begin
  select * into v_booking
  from public.bookings b
  where b.id = new.booking_id;

  select coalesce(sum(s.duration_minutes), 0)::integer into v_total_duration
  from public.booking_services bs
  join public.services s on s.id = bs.service_id
  where bs.booking_id = new.booking_id;

  v_day := extract(dow from (v_booking.starts_at at time zone 'Asia/Jakarta'))::smallint;

  select * into v_hours
  from public.branch_business_hours h
  where h.branch_id = v_booking.branch_id
    and h.day_of_week = v_day
    and h.is_open = true;

  if not found then
    raise exception 'Cabang Cipete tutup pada hari yang dipilih';
  end if;

  v_finish_time := (v_booking.starts_at at time zone 'Asia/Jakarta')::time
    + make_interval(mins => v_total_duration);

  if v_finish_time > v_hours.closes_at then
    raise exception 'Durasi layanan melewati jam tutup Cipete pukul % WIB', v_hours.closes_at;
  end if;

  return new;
end;
$$;

drop trigger if exists validate_booking_business_hours on public.bookings;
create trigger validate_booking_business_hours
before insert or update of starts_at, branch_id on public.bookings
for each row execute function public.validate_booking_business_hours();

drop trigger if exists validate_booking_service_fits_hours on public.booking_services;
create trigger validate_booking_service_fits_hours
after insert or update on public.booking_services
for each row execute function public.validate_booking_service_fits_hours();

revoke all on function public.validate_booking_business_hours() from public, anon, authenticated;
revoke all on function public.validate_booking_service_fits_hours() from public, anon, authenticated;
