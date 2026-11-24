create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = (select auth.uid())
$$;

create or replace function public.current_barber_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select b.id from public.barbers b where b.profile_id = (select auth.uid()) and b.is_active
$$;

revoke all on function public.current_app_role() from public, anon;
revoke all on function public.current_barber_id() from public, anon;
grant execute on function public.current_app_role() to authenticated;
grant execute on function public.current_barber_id() to authenticated;

revoke all on all tables in schema public from anon, authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.services, public.service_categories to anon, authenticated;
grant select (id, display_name) on public.barbers to anon, authenticated;
grant select on public.profiles to authenticated;
revoke update (role) on public.profiles from authenticated;
grant update (full_name, phone, updated_at) on public.profiles to authenticated;
grant select on public.customers, public.memberships, public.loyalty_stamps,
  public.loyalty_rewards, public.reward_redemptions, public.bookings,
  public.booking_services, public.queues, public.transactions,
  public.transaction_items, public.payments, public.receipts,
  public.notifications
to authenticated;

drop policy if exists "authenticated profiles read" on public.profiles;
drop policy if exists "profiles read self or staff" on public.profiles;
drop policy if exists "profiles update own" on public.profiles;
drop policy if exists "profiles update self without role escalation" on public.profiles;
create policy "profiles read self or staff" on public.profiles for select to authenticated
using ((select auth.uid()) = id or (select public.current_app_role()) in ('owner', 'admin_cashier'));
create policy "profiles update self without role escalation" on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id and role = (select public.current_app_role()));

drop policy if exists "public active services" on public.services;
drop policy if exists "staff service management" on public.services;
drop policy if exists "public active service categories" on public.service_categories;
drop policy if exists "public service categories" on public.service_categories;
drop policy if exists "staff category management" on public.service_categories;
create policy "public active services" on public.services for select to anon, authenticated
using (is_active = true);
create policy "public service categories" on public.service_categories for select to anon, authenticated
using (true);

drop policy if exists "own customer record" on public.customers;
drop policy if exists "customers read self or staff" on public.customers;
drop policy if exists "customers create self" on public.customers;
drop policy if exists "customers update self or staff" on public.customers;
create policy "customers read self or staff" on public.customers for select to authenticated
using (profile_id = (select auth.uid()) or (select public.current_app_role()) in ('owner','admin_cashier'));
create policy "customers create self" on public.customers for insert to authenticated
with check (profile_id = (select auth.uid()));

drop policy if exists "own memberships" on public.memberships;
drop policy if exists "memberships read self or staff" on public.memberships;
create policy "memberships read self or staff" on public.memberships for select to authenticated
using (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier'));

drop policy if exists "stamps read self or staff" on public.loyalty_stamps;
create policy "stamps read self or staff" on public.loyalty_stamps for select to authenticated
using (exists (select 1 from public.memberships m join public.customers c on c.id = m.customer_id
  where m.id = membership_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier'));
drop policy if exists "active rewards read" on public.loyalty_rewards;
create policy "active rewards read" on public.loyalty_rewards for select to anon, authenticated
using (is_active = true);
drop policy if exists "redemptions read self or staff" on public.reward_redemptions;
create policy "redemptions read self or staff" on public.reward_redemptions for select to authenticated
using (exists (select 1 from public.memberships m join public.customers c on c.id = m.customer_id
  where m.id = membership_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier'));
drop policy if exists "notifications read self" on public.notifications;
create policy "notifications read self" on public.notifications for select to authenticated
using (profile_id = (select auth.uid()));

drop policy if exists "bookings read own or staff" on public.bookings;
drop policy if exists "customers create own bookings" on public.bookings;
drop policy if exists "bookings update own or staff" on public.bookings;
create policy "bookings read own or staff" on public.bookings for select to authenticated
using (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier')
  or ((select public.current_app_role()) = 'barber' and barber_id = (select public.current_barber_id())));
create policy "customers create own bookings" on public.bookings for insert to authenticated
with check (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid())));
create policy "bookings update own or staff" on public.bookings for update to authenticated
using (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier')
  or ((select public.current_app_role()) = 'barber' and barber_id = (select public.current_barber_id())))
with check (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier')
  or ((select public.current_app_role()) = 'barber' and barber_id = (select public.current_barber_id())));

drop policy if exists "booking services read with booking" on public.booking_services;
drop policy if exists "booking services staff manage" on public.booking_services;
create policy "booking services read with booking" on public.booking_services for select to authenticated
using (exists (select 1 from public.bookings b where b.id = booking_id));
create policy "booking services staff manage" on public.booking_services for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'))
with check ((select public.current_app_role()) in ('owner','admin_cashier'));

drop policy if exists "queues read own or staff" on public.queues;
create policy "queues read own or staff" on public.queues for select to authenticated
using ((customer_id is not null and exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid())))
  or (select public.current_app_role()) in ('owner','admin_cashier')
  or ((select public.current_app_role()) = 'barber' and barber_id = (select public.current_barber_id())));

drop policy if exists "transactions read own or staff" on public.transactions;
drop policy if exists "transaction items read own or staff" on public.transaction_items;
drop policy if exists "payments read own or staff" on public.payments;
drop policy if exists "receipts read own or staff" on public.receipts;
create policy "transactions read own or staff" on public.transactions for select to authenticated
using ((customer_id is not null and exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid())))
  or (select public.current_app_role()) in ('owner','admin_cashier'));
create policy "transaction items read own or staff" on public.transaction_items for select to authenticated
using (exists (select 1 from public.transactions t where t.id = transaction_id));
create policy "payments read own or staff" on public.payments for select to authenticated
using (exists (select 1 from public.transactions t where t.id = transaction_id));
create policy "receipts read own or staff" on public.receipts for select to authenticated
using (exists (select 1 from public.transactions t where t.id = transaction_id));
drop policy if exists "barber schedules staff read" on public.barber_schedules;
drop policy if exists "active barbers public read" on public.barbers;
create policy "active barbers public read" on public.barbers for select to anon, authenticated
using (is_active = true);
create policy "barber schedules staff read" on public.barber_schedules for select to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier')
  or ((select public.current_app_role()) = 'barber' and barber_id = (select public.current_barber_id())));
drop policy if exists "audit logs owner read" on public.audit_logs;
create policy "audit logs owner read" on public.audit_logs for select to authenticated
using ((select public.current_app_role()) = 'owner');

alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.memberships enable row level security;
alter table public.loyalty_stamps enable row level security;
alter table public.loyalty_rewards enable row level security;
alter table public.reward_redemptions enable row level security;
alter table public.notifications enable row level security;
alter table public.services enable row level security;
alter table public.service_categories enable row level security;
alter table public.bookings enable row level security;
alter table public.booking_services enable row level security;
alter table public.queues enable row level security;
alter table public.transactions enable row level security;
alter table public.transaction_items enable row level security;
alter table public.payments enable row level security;
alter table public.receipts enable row level security;
alter table public.barbers enable row level security;
alter table public.barber_schedules enable row level security;
alter table public.products enable row level security;
alter table public.inventory_movements enable row level security;
alter table public.expenses enable row level security;
alter table public.cashier_sessions enable row level security;
alter table public.audit_logs enable row level security;
alter table public.app_settings enable row level security;
