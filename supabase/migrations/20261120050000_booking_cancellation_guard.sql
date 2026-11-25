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

  select p.role into v_role
  from public.profiles p
  where p.id = auth.uid();

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
    where booking_id = p_booking_id
      and status in ('waiting', 'called');
    return true;
  end if;

  return false;
end;
$$;

revoke all on function public.cancel_own_booking(uuid) from public, anon;
grant execute on function public.cancel_own_booking(uuid) to authenticated;
