create or replace function public.admin_list_bookings(
  p_start timestamptz,
  p_end timestamptz
)
returns table (
  id uuid,
  starts_at timestamptz,
  status text,
  notes text,
  customer_name text,
  customer_phone text,
  barber_name text,
  service_names text,
  queue_number integer,
  queue_status text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce((select public.current_user_is_active_staff()), false) then
    raise exception 'Akses hanya untuk owner atau admin staf aktif';
  end if;

  if p_start is null
    or p_end is null
    or p_end <= p_start
    or p_end - p_start > interval '31 days' then
    raise exception 'Rentang tanggal booking tidak valid';
  end if;

  return query
  select
    b.id,
    b.starts_at,
    b.status,
    b.notes,
    c.full_name,
    c.phone,
    br.display_name,
    coalesce(string_agg(s.name, ', ' order by s.name), 'Layanan tidak tersedia'),
    q.queue_number,
    q.status
  from public.bookings b
  join public.customers c on c.id = b.customer_id
  left join public.barbers br on br.id = b.barber_id
  left join public.booking_services bs on bs.booking_id = b.id
  left join public.services s on s.id = bs.service_id
  left join public.queues q on q.booking_id = b.id
  where b.starts_at >= p_start
    and b.starts_at < p_end
  group by b.id, c.id, br.id, q.id
  order by b.starts_at, q.queue_number nulls last;
end;
$$;

create or replace function public.admin_update_booking_status(
  p_booking_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_current_status text;
begin
  if not coalesce((select public.current_user_is_active_staff()), false) then
    raise exception 'Akses hanya untuk owner atau admin staf aktif';
  end if;

  if p_status not in ('confirmed', 'checked_in', 'completed', 'cancelled', 'no_show') then
    raise exception 'Status booking yang diminta tidak valid';
  end if;

  select b.status
  into v_current_status
  from public.bookings b
  where b.id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking tidak ditemukan';
  end if;

  if not (
    (v_current_status = 'pending' and p_status in ('confirmed', 'cancelled'))
    or (v_current_status = 'confirmed' and p_status in ('checked_in', 'cancelled', 'no_show'))
    or (v_current_status = 'checked_in' and p_status = 'completed')
  ) then
    raise exception 'Perubahan status booking tidak diizinkan';
  end if;

  update public.bookings
  set status = p_status,
      updated_at = now()
  where id = p_booking_id;

  if p_status = 'checked_in' then
    update public.queues
    set status = 'called',
        updated_at = now()
    where booking_id = p_booking_id
      and status = 'waiting';
  elsif p_status = 'completed' then
    update public.queues
    set status = 'completed',
        updated_at = now()
    where booking_id = p_booking_id
      and status in ('waiting', 'called', 'serving');
  elsif p_status = 'cancelled' then
    update public.queues
    set status = 'cancelled',
        updated_at = now()
    where booking_id = p_booking_id
      and status in ('waiting', 'called');
  elsif p_status = 'no_show' then
    update public.queues
    set status = 'no_show',
        updated_at = now()
    where booking_id = p_booking_id
      and status in ('waiting', 'called');
  end if;

  return true;
end;
$$;

revoke all on function public.admin_list_bookings(timestamptz, timestamptz) from public, anon;
revoke all on function public.admin_update_booking_status(uuid, text) from public, anon;
grant execute on function public.admin_list_bookings(timestamptz, timestamptz) to authenticated;
grant execute on function public.admin_update_booking_status(uuid, text) to authenticated;
