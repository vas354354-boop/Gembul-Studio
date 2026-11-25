create extension if not exists pgcrypto;

create type public.app_role as enum ('owner', 'admin_cashier', 'barber', 'customer');

create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null,
  phone text,
  role public.app_role not null default 'customer',
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.customers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  full_name text not null,
  phone text unique,
  member_code text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.barbers (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid unique references public.profiles(id) on delete set null,
  display_name text not null,
  commission_percent numeric(5,2) not null default 0 check (commission_percent between 0 and 100),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.service_categories (id uuid primary key default gen_random_uuid(), name text unique not null, sort_order integer not null default 0, created_at timestamptz not null default now());
create table public.services (
  id uuid primary key default gen_random_uuid(),
  category_id uuid references public.service_categories(id),
  name text not null,
  description text,
  price numeric(14,2) not null check (price >= 0),
  duration_minutes integer not null check (duration_minutes > 0),
  earns_loyalty_stamp boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.barber_schedules (
  id uuid primary key default gen_random_uuid(),
  barber_id uuid not null references public.barbers(id) on delete cascade,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  check (ends_at > starts_at),
  created_at timestamptz not null default now()
);
create unique index barber_schedules_barber_time_idx on public.barber_schedules (barber_id, starts_at, ends_at);

create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id),
  barber_id uuid references public.barbers(id),
  starts_at timestamptz not null,
  status text not null default 'pending' check (status in ('pending','confirmed','checked_in','cancelled','no_show','completed')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.booking_services (
  booking_id uuid not null references public.bookings(id) on delete cascade,
  service_id uuid not null references public.services(id),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  primary key (booking_id, service_id)
);

create table public.queues (
  id uuid primary key default gen_random_uuid(),
  queue_date date not null default current_date,
  queue_number integer not null check (queue_number > 0),
  customer_id uuid references public.customers(id),
  booking_id uuid unique references public.bookings(id),
  barber_id uuid references public.barbers(id),
  status text not null default 'waiting' check (status in ('waiting','called','serving','completed','cancelled','no_show')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (queue_date, queue_number)
);

create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  transaction_number text unique not null,
  customer_id uuid references public.customers(id),
  cashier_id uuid references public.profiles(id),
  subtotal numeric(14,2) not null check (subtotal >= 0),
  discount numeric(14,2) not null default 0 check (discount >= 0),
  total numeric(14,2) not null check (total >= 0),
  status text not null default 'completed' check (status in ('completed','refunded','cancelled')),
  paid_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.transaction_items (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  item_type text not null check (item_type in ('service','product','reward')),
  item_id uuid,
  description text not null,
  quantity integer not null default 1 check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  barber_id uuid references public.barbers(id)
);
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid not null references public.transactions(id) on delete cascade,
  method text not null check (method in ('cash','qris','bank_transfer')),
  amount numeric(14,2) not null check (amount >= 0),
  reference text,
  created_at timestamptz not null default now()
);
create table public.receipts (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid unique not null references public.transactions(id) on delete cascade,
  receipt_number text unique not null,
  pdf_storage_path text,
  created_at timestamptz not null default now()
);

create table public.memberships (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid unique not null references public.customers(id) on delete cascade,
  status text not null default 'active' check (status in ('active','inactive')),
  member_since timestamptz not null default now()
);
create table public.loyalty_stamps (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null references public.memberships(id) on delete cascade,
  transaction_id uuid references public.transactions(id),
  is_valid boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.loyalty_rewards (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  required_stamps integer not null check (required_stamps > 0),
  reward_service_id uuid references public.services(id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);
create table public.reward_redemptions (
  id uuid primary key default gen_random_uuid(),
  membership_id uuid not null references public.memberships(id),
  reward_id uuid not null references public.loyalty_rewards(id),
  transaction_id uuid references public.transactions(id),
  redeemed_at timestamptz not null default now()
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  category text not null,
  description text,
  amount numeric(14,2) not null check (amount >= 0),
  expense_date date not null default current_date,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create table public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  sku text unique,
  purchase_price numeric(14,2) not null default 0 check (purchase_price >= 0),
  selling_price numeric(14,2) not null check (selling_price >= 0),
  stock_quantity integer not null default 0 check (stock_quantity >= 0),
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table public.inventory_movements (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id),
  movement_type text not null check (movement_type in ('purchase','sale','adjustment','refund','damaged','expired')),
  quantity integer not null,
  note text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);
create table public.cashier_sessions (
  id uuid primary key default gen_random_uuid(),
  cashier_id uuid not null references public.profiles(id),
  opened_at timestamptz not null default now(),
  closed_at timestamptz,
  opening_cash numeric(14,2) not null default 0,
  closing_cash numeric(14,2),
  status text not null default 'open' check (status in ('open','closed'))
);
create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  title text not null,
  body text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid references public.profiles(id),
  action text not null,
  entity_type text not null,
  entity_id text,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz not null default now()
);
create table public.app_settings (key text primary key, value jsonb not null, updated_at timestamptz not null default now());

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = ''
as $$
  select p.role from public.profiles p where p.id = (select auth.uid())
$$;

create or replace function public.set_updated_at() returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

do $$
declare table_name text;
begin
  foreach table_name in array array['profiles','customers','barbers','services','bookings','queues','transactions','products'] loop
    execute format('create trigger set_updated_at_%I before update on public.%I for each row execute function public.set_updated_at()', table_name, table_name);
  end loop;
end $$;

alter table public.profiles enable row level security;
alter table public.customers enable row level security;
alter table public.barbers enable row level security;
alter table public.services enable row level security;
alter table public.bookings enable row level security;
alter table public.queues enable row level security;
alter table public.transactions enable row level security;
alter table public.receipts enable row level security;
alter table public.memberships enable row level security;
alter table public.loyalty_stamps enable row level security;
alter table public.reward_redemptions enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.services, public.service_categories to anon, authenticated;
grant select on public.barbers to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select on public.customers, public.memberships, public.loyalty_stamps, public.loyalty_rewards, public.reward_redemptions, public.bookings, public.booking_services, public.queues, public.transactions, public.transaction_items, public.payments, public.receipts, public.notifications to authenticated;
grant select, insert, update, delete on public.services, public.service_categories to authenticated;
grant select, insert, update on public.bookings, public.booking_services, public.queues to authenticated;
grant select, insert, update on public.customers, public.memberships, public.loyalty_stamps, public.loyalty_rewards, public.reward_redemptions, public.transactions, public.transaction_items, public.payments, public.receipts, public.barbers, public.barber_schedules, public.products, public.inventory_movements, public.expenses, public.cashier_sessions, public.notifications, public.audit_logs, public.app_settings to authenticated;

create policy "profiles read self or staff" on public.profiles for select to authenticated
using ((select auth.uid()) = id or (select public.current_app_role()) in ('owner', 'admin_cashier'));
create policy "profiles update self without role escalation" on public.profiles for update to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id and role = (select public.current_app_role()));

create policy "public active service categories" on public.service_categories for select to anon, authenticated using (true);
create policy "public active services" on public.services for select to anon, authenticated using (is_active = true);
create policy "staff service management" on public.services for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'))
with check ((select public.current_app_role()) in ('owner','admin_cashier'));
create policy "staff category management" on public.service_categories for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'))
with check ((select public.current_app_role()) in ('owner','admin_cashier'));

create policy "customers read self or staff" on public.customers for select to authenticated
using (profile_id = (select auth.uid()) or (select public.current_app_role()) in ('owner','admin_cashier'));
create policy "customers create self" on public.customers for insert to authenticated
with check (profile_id = (select auth.uid()));
create policy "customers update self or staff" on public.customers for update to authenticated
using (profile_id = (select auth.uid()) or (select public.current_app_role()) in ('owner','admin_cashier'))
with check (profile_id = (select auth.uid()) or (select public.current_app_role()) in ('owner','admin_cashier'));

create policy "memberships read self or staff" on public.memberships for select to authenticated
using (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier'));
create policy "stamps read self or staff" on public.loyalty_stamps for select to authenticated
using (exists (select 1 from public.memberships m join public.customers c on c.id = m.customer_id where m.id = membership_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier'));
create policy "rewards read active" on public.loyalty_rewards for select to anon, authenticated using (is_active);
create policy "reward redemption read self or staff" on public.reward_redemptions for select to authenticated
using (exists (select 1 from public.memberships m join public.customers c on c.id = m.customer_id where m.id = membership_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier'));
create policy "notifications read self" on public.notifications for select to authenticated
using (profile_id = (select auth.uid()));

create policy "bookings read own or staff" on public.bookings for select to authenticated
using (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier')
  or (select public.current_app_role()) = 'barber' and exists (select 1 from public.barbers b where b.id = barber_id and b.profile_id = (select auth.uid())));
create policy "customers create own bookings" on public.bookings for insert to authenticated
with check (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid())));
create policy "bookings update own or staff" on public.bookings for update to authenticated
using (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier')
  or (select public.current_app_role()) = 'barber' and exists (select 1 from public.barbers b where b.id = barber_id and b.profile_id = (select auth.uid())))
with check (exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid()))
  or (select public.current_app_role()) in ('owner','admin_cashier')
  or (select public.current_app_role()) = 'barber' and exists (select 1 from public.barbers b where b.id = barber_id and b.profile_id = (select auth.uid())));
create policy "booking services follow booking access" on public.booking_services for select to authenticated
using (exists (select 1 from public.bookings b where b.id = booking_id));
create policy "staff manage booking services" on public.booking_services for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'))
with check ((select public.current_app_role()) in ('owner','admin_cashier'));

create policy "queues read own or staff" on public.queues for select to authenticated
using ((customer_id is not null and exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid())))
  or (select public.current_app_role()) in ('owner','admin_cashier')
  or (select public.current_app_role()) = 'barber' and exists (select 1 from public.barbers b where b.id = barber_id and b.profile_id = (select auth.uid())));
create policy "staff manage queues" on public.queues for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier','barber'))
with check ((select public.current_app_role()) in ('owner','admin_cashier','barber'));

create policy "transactions read own or staff" on public.transactions for select to authenticated
using ((customer_id is not null and exists (select 1 from public.customers c where c.id = customer_id and c.profile_id = (select auth.uid())))
  or (select public.current_app_role()) in ('owner','admin_cashier'));
create policy "transaction items read own or staff" on public.transaction_items for select to authenticated
using (exists (select 1 from public.transactions t where t.id = transaction_id));
create policy "payments read own or staff" on public.payments for select to authenticated
using (exists (select 1 from public.transactions t where t.id = transaction_id));
create policy "receipts read own or staff" on public.receipts for select to authenticated
using (exists (select 1 from public.transactions t where t.id = transaction_id));
create policy "barbers public active read" on public.barbers for select to anon, authenticated using (is_active);
create policy "barber schedules staff read" on public.barber_schedules for select to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier')
  or exists (select 1 from public.barbers b where b.id = barber_id and b.profile_id = (select auth.uid())));
create policy "barber schedules staff manage" on public.barber_schedules for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'))
with check ((select public.current_app_role()) in ('owner','admin_cashier'));

create policy "staff manage operational data" on public.products for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'))
with check ((select public.current_app_role()) in ('owner','admin_cashier'));
create policy "staff manage expenses" on public.expenses for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'))
with check ((select public.current_app_role()) in ('owner','admin_cashier'));
create policy "staff manage inventory movements" on public.inventory_movements for all to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'))
with check ((select public.current_app_role()) in ('owner','admin_cashier'));
create policy "cashier sessions read own or owner" on public.cashier_sessions for select to authenticated
using (cashier_id = (select auth.uid()) or (select public.current_app_role()) = 'owner');
create policy "cashier sessions manage own or owner" on public.cashier_sessions for all to authenticated
using (cashier_id = (select auth.uid()) and (select public.current_app_role()) in ('owner','admin_cashier')
  or (select public.current_app_role()) = 'owner')
with check (cashier_id = (select auth.uid()) and (select public.current_app_role()) in ('owner','admin_cashier')
  or (select public.current_app_role()) = 'owner');
create policy "owner manages app settings" on public.app_settings for all to authenticated
using ((select public.current_app_role()) = 'owner')
with check ((select public.current_app_role()) = 'owner');
create policy "staff can read app settings" on public.app_settings for select to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier','barber'));
create policy "staff can read audit logs" on public.audit_logs for select to authenticated
using ((select public.current_app_role()) in ('owner','admin_cashier'));

insert into public.service_categories(name, sort_order) values
  ('Potong Rambut', 1),
  ('Perawatan', 2),
  ('Styling & Warna', 3)
on conflict do nothing;

insert into public.services(category_id, name, price, duration_minutes, earns_loyalty_stamp, is_active)
select c.id, s.name, s.price, s.duration_minutes, s.earns_loyalty_stamp, true
from public.service_categories c
cross join lateral (values
  ('Potong rambut dewasa', 25000::numeric, 45, true),
  ('Potong rambut anak-anak', 20000::numeric, 30, false),
  ('Potong jenggot/kumis', 10000::numeric, 20, false),
  ('Cuci rambut', 10000::numeric, 20, false),
  ('Styling rambut', 5000::numeric, 15, false),
  ('Semir/warna rambut', 100000::numeric, 90, false),
  ('Hair treatment', 25000::numeric, 30, false),
  ('Hair wash + styling', 15000::numeric, 30, false)
) as s(name, price, duration_minutes, earns_loyalty_stamp)
where (c.name = 'Potong Rambut' and s.name in ('Potong rambut dewasa','Potong rambut anak-anak','Potong jenggot/kumis'))
   or (c.name = 'Perawatan' and s.name in ('Cuci rambut','Hair treatment','Hair wash + styling'))
   or (c.name = 'Styling & Warna' and s.name in ('Styling rambut','Semir/warna rambut'))
  on conflict do nothing;

insert into public.app_settings(key, value) values
  ('loyalty', '{"required_stamps":5,"qualified_service":"adult_haircut","stamp_only_after_payment":true}'::jsonb),
  ('booking', '{"allow_cancellation":true,"cancellation_notice_minutes":60}'::jsonb),
  ('business', '{"name":"Gembul Studio","tagline":"Seni dalam Setiap Potongan","currency":"IDR"}'::jsonb);
