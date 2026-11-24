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
    select 1 from public.barbers b
    where b.id = p_barber_id and b.is_active = true
  ) then
    raise exception 'Barber tidak tersedia';
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

  insert into public.bookings (customer_id, barber_id, starts_at, status, notes)
  values (v_customer.id, p_barber_id, p_starts_at, 'confirmed', left(coalesce(p_notes, ''), 500))
  returning id into v_booking_id;

  insert into public.booking_services (booking_id, service_id, unit_price)
  select v_booking_id, s.id, s.price
  from public.services s
  where s.id = any(p_service_ids)
  on conflict (booking_id, service_id) do update
  set unit_price = excluded.unit_price;

  v_queue_date := (p_starts_at at time zone 'Asia/Jakarta')::date;

  perform pg_advisory_xact_lock(hashtext(v_queue_date::text));

  select coalesce(max(queue_number), 0) + 1
  into v_queue_number
  from public.queues
  where queue_date = v_queue_date;

  insert into public.queues (
    queue_date,
    queue_number,
    customer_id,
    booking_id,
    barber_id,
    status
  ) values (
    v_queue_date,
    v_queue_number,
    v_customer.id,
    v_booking_id,
    p_barber_id,
    'waiting'
  ) returning id into v_queue_id;

  return jsonb_build_object(
    'booking_id', v_booking_id,
    'queue_id', v_queue_id,
    'queue_number', v_queue_number,
    'queue_date', v_queue_date,
    'starts_at', p_starts_at
  );
end;
$$;

revoke all on function public.create_customer_booking(uuid[], uuid, timestamptz, text) from public, anon;
grant execute on function public.create_customer_booking(uuid[], uuid, timestamptz, text) to authenticated;

create or replace function public.cancel_own_booking(p_booking_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id uuid;
  v_role public.app_role;
begin
  select c.id into v_customer_id
  from public.customers c
  where c.profile_id = auth.uid();

  select role into v_role
  from public.profiles
  where id = auth.uid();

  if v_role in ('owner', 'admin_cashier') then
    update public.bookings
    set status = 'cancelled', updated_at = now()
    where id = p_booking_id
      and status in ('pending', 'confirmed');
  else
    update public.bookings
    set status = 'cancelled', updated_at = now()
    where id = p_booking_id
      and customer_id = v_customer_id
      and status in ('pending', 'confirmed');
  end if;

  if found then
    update public.queues
    set status = 'cancelled', updated_at = now()
    where booking_id = p_booking_id;
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.cancel_own_booking(uuid) from public, anon;
grant execute on function public.cancel_own_booking(uuid) to authenticated;
