create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  created_customer_id uuid;
  customer_name text;
  customer_phone text;
begin
  customer_name := coalesce(
    nullif(left(trim(new.raw_user_meta_data ->> 'full_name'), 100), ''),
    nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
    'Pelanggan Gembul'
  );
  customer_phone := nullif(left(trim(coalesce(new.phone, new.raw_user_meta_data ->> 'phone', '')), 30), '');

  insert into public.profiles (id, full_name, phone, role)
  values (new.id, customer_name, customer_phone, 'customer')
  on conflict (id) do nothing;

  begin
    insert into public.customers (profile_id, full_name, phone, member_code)
    values (
      new.id,
      customer_name,
      customer_phone,
      'GS-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
    )
    on conflict (profile_id) do update
    set full_name = excluded.full_name,
        phone = coalesce(customers.phone, excluded.phone)
    returning id into created_customer_id;
  exception
    when unique_violation then
      insert into public.customers (profile_id, full_name, member_code)
      values (
        new.id,
        customer_name,
        'GS-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12))
      )
      on conflict (profile_id) do update
      set full_name = excluded.full_name
      returning id into created_customer_id;
  end;

  insert into public.memberships (customer_id)
  values (created_customer_id)
  on conflict (customer_id) do nothing;

  return new;
end;
$$;

revoke all on function public.handle_new_auth_user() from public, anon, authenticated;

drop trigger if exists on_auth_user_created_gembul on auth.users;
create trigger on_auth_user_created_gembul
  after insert on auth.users
  for each row execute function public.handle_new_auth_user();
