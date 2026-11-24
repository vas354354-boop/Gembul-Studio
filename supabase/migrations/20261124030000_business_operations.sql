alter table public.customers
  add column if not exists email text,
  add column if not exists birth_date date,
  add column if not exists notes text,
  add column if not exists marketing_opt_in boolean not null default false;

create unique index if not exists customers_email_lower_uidx
  on public.customers (lower(email))
  where email is not null;

alter table public.products
  add column if not exists category text not null default 'Umum',
  add column if not exists description text,
  add column if not exists minimum_stock integer not null default 0 check (minimum_stock >= 0),
  add column if not exists unit text not null default 'pcs';

alter table public.transactions
  add column if not exists idempotency_key uuid,
  add column if not exists voucher_code text,
  add column if not exists amount_tendered numeric(14,2) not null default 0,
  add column if not exists change_due numeric(14,2) not null default 0;

alter table public.transaction_items
  add column if not exists unit_cost numeric(14,2) not null default 0 check (unit_cost >= 0);

create unique index if not exists transactions_idempotency_key_uidx
  on public.transactions (idempotency_key)
  where idempotency_key is not null;

create sequence if not exists public.transaction_number_seq;
revoke all on sequence public.transaction_number_seq from public, anon, authenticated;

create table if not exists public.suppliers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text,
  email text,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.purchases (
  id uuid primary key default gen_random_uuid(),
  purchase_number text unique not null,
  supplier_id uuid references public.suppliers(id),
  total numeric(14,2) not null check (total >= 0),
  status text not null default 'received' check (status in ('received', 'cancelled')),
  notes text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.purchases(id) on delete cascade,
  product_id uuid not null references public.products(id),
  quantity integer not null check (quantity > 0),
  unit_cost numeric(14,2) not null check (unit_cost >= 0)
);

create table if not exists public.transaction_loyalty_redemptions (
  transaction_id uuid primary key references public.transactions(id),
  membership_id uuid not null references public.memberships(id),
  reward_id uuid not null references public.loyalty_rewards(id),
  stamp_ids uuid[] not null,
  created_at timestamptz not null default now()
);

create table if not exists public.transaction_refunds (
  id uuid primary key default gen_random_uuid(),
  transaction_id uuid unique not null references public.transactions(id),
  refund_number text unique not null,
  amount numeric(14,2) not null check (amount >= 0),
  reason text not null,
  refunded_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.promotions (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  name text not null,
  discount_type text not null check (discount_type in ('fixed', 'percent')),
  discount_value numeric(14,2) not null check (discount_value > 0),
  minimum_transaction numeric(14,2) not null default 0 check (minimum_transaction >= 0),
  max_redemptions integer check (max_redemptions is null or max_redemptions > 0),
  per_customer_limit integer not null default 1 check (per_customer_limit > 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_active boolean not null default true,
  terms text,
  created_by uuid references public.profiles(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at),
  check (discount_type <> 'percent' or discount_value <= 100)
);

create table if not exists public.promotion_redemptions (
  id uuid primary key default gen_random_uuid(),
  promotion_id uuid not null references public.promotions(id),
  customer_id uuid not null references public.customers(id),
  transaction_id uuid unique not null references public.transactions(id),
  discount_amount numeric(14,2) not null check (discount_amount >= 0),
  redeemed_at timestamptz not null default now()
);

alter table public.promotion_redemptions
  add column if not exists is_refunded boolean not null default false;

create table if not exists public.marketing_campaigns (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  segment text not null,
  message_template text not null,
  recipient_count integer not null default 0 check (recipient_count >= 0),
  prepared_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);

create table if not exists public.marketing_campaign_recipients (
  campaign_id uuid not null references public.marketing_campaigns(id) on delete cascade,
  customer_id uuid not null references public.customers(id),
  chat_opened_at timestamptz,
  primary key (campaign_id, customer_id)
);

insert into public.loyalty_rewards(name,required_stamps,reward_service_id,is_active)
select 'Potong Rambut Gratis',5,s.id,true
from public.services s
where s.earns_loyalty_stamp and s.is_active
  and not exists(select 1 from public.loyalty_rewards r where r.is_active and r.required_stamps=5)
order by s.created_at,s.id
limit 1;

alter table public.suppliers enable row level security;
alter table public.purchases enable row level security;
alter table public.purchase_items enable row level security;
alter table public.transaction_loyalty_redemptions enable row level security;
alter table public.transaction_refunds enable row level security;
alter table public.promotions enable row level security;
alter table public.promotion_redemptions enable row level security;
alter table public.marketing_campaigns enable row level security;
alter table public.marketing_campaign_recipients enable row level security;

revoke all on public.suppliers, public.purchases, public.purchase_items,
  public.transaction_loyalty_redemptions, public.transaction_refunds,
  public.promotions, public.promotion_redemptions,
  public.marketing_campaigns, public.marketing_campaign_recipients
from anon, authenticated;

create or replace function public.admin_create_customer(
  p_full_name text,
  p_phone text default null,
  p_email text default null,
  p_birth_date date default null,
  p_marketing_opt_in boolean default false
)
returns table (id uuid, full_name text, phone text, email text, member_code text)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_customer_id uuid;
  v_name text;
  v_phone text;
  v_email text;
begin
  if not coalesce((select public.current_user_is_active_staff()), false) then
    raise exception 'Akses hanya untuk staf aktif';
  end if;
  v_name := trim(regexp_replace(coalesce(p_full_name, ''), '\s+', ' ', 'g'));
  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  v_email := nullif(lower(trim(coalesce(p_email, ''))), '');
  if char_length(v_name) < 2 or char_length(v_name) > 100 then
    raise exception 'Nama pelanggan harus 2 sampai 100 karakter';
  end if;
  if v_phone is null and v_email is null then
    raise exception 'Nomor WhatsApp atau email wajib diisi';
  end if;
  if v_phone is not null and char_length(v_phone) > 30 then
    raise exception 'Nomor WhatsApp maksimal 30 karakter';
  end if;
  if v_email is not null and (char_length(v_email) > 254 or v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then
    raise exception 'Format email tidak valid';
  end if;
  if p_birth_date is not null and p_birth_date > current_date then
    raise exception 'Tanggal lahir tidak boleh di masa depan';
  end if;
  if v_phone is not null and exists (select 1 from public.customers c where c.phone = v_phone) then
    raise exception 'Nomor WhatsApp sudah terdaftar';
  end if;
  if v_email is not null and exists (select 1 from public.customers c where lower(c.email)=v_email) then
    raise exception 'Email sudah terdaftar';
  end if;

  insert into public.customers (full_name, phone, email, birth_date, member_code, notes, marketing_opt_in)
  values (
    v_name, v_phone, v_email, p_birth_date,
    'GS-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12)),
    null, coalesce(p_marketing_opt_in, false)
  )
  returning customers.id into v_customer_id;

  insert into public.memberships (customer_id) values (v_customer_id)
  on conflict (customer_id) do nothing;

  return query
  select c.id, c.full_name, c.phone, c.email, c.member_code
  from public.customers c where c.id = v_customer_id;
exception
  when unique_violation then
    raise exception 'Nomor WhatsApp atau email sudah terdaftar';
end;
$$;

create or replace function public.admin_search_customers(
  p_search text default null,
  p_segment text default 'all',
  p_limit integer default 50,
  p_offset integer default 0
)
returns table (
  id uuid,
  full_name text,
  phone text,
  email text,
  member_code text,
  birth_date date,
  marketing_opt_in boolean,
  notes text,
  membership_status text,
  visit_count bigint,
  transaction_count bigint,
  total_spend numeric,
  last_visit timestamptz,
  segment text
)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce((select public.current_user_is_active_staff()), false) then
    raise exception 'Akses hanya untuk staf aktif';
  end if;
  if p_segment not in ('all','new','active','loyal','vip','inactive','lost','birthday') then
    raise exception 'Segment pelanggan tidak valid';
  end if;

  return query
  with customer_stats as (
    select c.id as customer_id,
      count(t.id) filter (where t.status = 'completed')::bigint as transactions,
      coalesce(sum(t.total) filter (where t.status = 'completed'), 0)::numeric as spend,
      max(t.created_at) filter (where t.status = 'completed') as last_seen,
      count(t.id) filter (where t.status = 'completed' and t.created_at >= now() - interval '90 days')::bigint as recent_transactions,
      count(t.id) filter (where t.status = 'completed' and t.created_at >= now() - interval '30 days')::bigint as newest_transactions
    from public.customers c
    left join public.transactions t on t.customer_id = c.id
    group by c.id
  ), classified as (
    select c.id, c.full_name, c.phone, c.email, c.member_code, c.birth_date,
      c.marketing_opt_in, c.notes, coalesce(m.status, 'inactive') as member_status,
      s.transactions, s.spend, s.last_seen, s.recent_transactions, s.newest_transactions,
      case
        when c.birth_date is not null
          and extract(month from c.birth_date) = extract(month from (now() at time zone 'Asia/Jakarta')::date)
          and extract(day from c.birth_date) = extract(day from (now() at time zone 'Asia/Jakarta')::date) then 'birthday'
        when s.transactions >= 20 then 'vip'
        when s.transactions >= 5 and s.last_seen >= now() - interval '90 days' then 'loyal'
        when s.transactions > 0 and s.last_seen >= now() - interval '60 days' then 'active'
        when s.last_seen < now() - interval '90 days' then 'lost'
        when s.last_seen < now() - interval '30 days' then 'inactive'
        else 'new'
      end as customer_segment
    from public.customers c
    left join public.memberships m on m.customer_id = c.id
    join customer_stats s on s.customer_id = c.id
  )
  select x.id, x.full_name, x.phone, x.email, x.member_code, x.birth_date,
    x.marketing_opt_in, x.notes, x.member_status,
    x.transactions, x.transactions, x.spend, x.last_seen, x.customer_segment
  from classified x
  where (
      coalesce(trim(p_search), '') = ''
      or x.full_name ilike '%' || trim(p_search) || '%'
      or coalesce(x.phone, '') ilike '%' || trim(p_search) || '%'
      or coalesce(x.email, '') ilike '%' || trim(p_search) || '%'
      or x.member_code ilike '%' || trim(p_search) || '%'
    )
    and (p_segment = 'all' or x.customer_segment = p_segment)
  order by x.last_seen desc nulls last, x.full_name
  limit greatest(1, least(coalesce(p_limit, 50), 100))
  offset greatest(coalesce(p_offset, 0), 0);
end;
$$;

create or replace function public.admin_update_customer(
  p_customer_id uuid,
  p_full_name text,
  p_phone text,
  p_email text,
  p_birth_date date,
  p_notes text,
  p_marketing_opt_in boolean
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text;
  v_phone text;
  v_email text;
begin
  if not coalesce((select public.current_user_is_active_staff()), false) then
    raise exception 'Akses hanya untuk staf aktif';
  end if;
  v_name := trim(regexp_replace(coalesce(p_full_name, ''), '\s+', ' ', 'g'));
  v_phone := nullif(trim(coalesce(p_phone, '')), '');
  v_email := nullif(lower(trim(coalesce(p_email, ''))), '');
  if char_length(v_name) < 2 or char_length(v_name) > 100 then raise exception 'Nama pelanggan tidak valid'; end if;
  if v_phone is not null and char_length(v_phone) > 30 then raise exception 'Nomor WhatsApp tidak valid'; end if;
  if v_email is not null and (char_length(v_email) > 254 or v_email !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$') then raise exception 'Format email tidak valid'; end if;
  if p_birth_date is not null and p_birth_date > current_date then raise exception 'Tanggal lahir tidak boleh di masa depan'; end if;
  if v_email is not null and exists (select 1 from public.customers c where c.id<>p_customer_id and lower(c.email)=v_email) then raise exception 'Email sudah digunakan pelanggan lain'; end if;

  update public.customers c
  set full_name = v_name, phone = v_phone, email = v_email, birth_date = p_birth_date,
      notes = left(trim(coalesce(p_notes, '')), 2000),
      marketing_opt_in = coalesce(p_marketing_opt_in, false), updated_at = now()
  where c.id = p_customer_id;
  if not found then raise exception 'Pelanggan tidak ditemukan'; end if;
  return true;
exception
  when unique_violation then raise exception 'Nomor WhatsApp atau email sudah digunakan pelanggan lain';
end;
$$;

create or replace function public.pos_catalog()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not coalesce((select public.current_user_is_active_staff()), false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  return jsonb_build_object(
    'services', coalesce((select jsonb_agg(jsonb_build_object('id',s.id,'name',s.name,'price',s.price,'earns_loyalty_stamp',s.earns_loyalty_stamp) order by s.name) from public.services s where s.is_active), '[]'::jsonb),
    'products', coalesce((select jsonb_agg(jsonb_build_object('id',p.id,'name',p.name,'sku',p.sku,'price',p.selling_price,'stock',p.stock_quantity) order by p.name) from public.products p where p.is_active), '[]'::jsonb),
    'barbers', coalesce((select jsonb_agg(jsonb_build_object('id',b.id,'name',b.display_name) order by b.display_name) from public.barbers b where b.is_active), '[]'::jsonb),
    'rewards', coalesce((select jsonb_agg(jsonb_build_object('id',r.id,'name',r.name,'required_stamps',r.required_stamps,'service_id',r.reward_service_id) order by r.required_stamps) from public.loyalty_rewards r where r.is_active), '[]'::jsonb)
  );
end;
$$;

create or replace function public.create_pos_transaction(
  p_customer_id uuid,
  p_barber_id uuid,
  p_service_ids uuid[],
  p_product_items jsonb,
  p_discount numeric,
  p_voucher_code text,
  p_redeem_reward boolean,
  p_payment_method text,
  p_amount_tendered numeric,
  p_idempotency_key uuid
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_product record;
  v_product_data public.products%rowtype;
  v_service record;
  v_customer public.customers%rowtype;
  v_membership public.memberships%rowtype;
  v_reward public.loyalty_rewards%rowtype;
  v_promotion public.promotions%rowtype;
  v_existing public.transactions%rowtype;
  v_transaction_id uuid;
  v_receipt_id uuid;
  v_transaction_number text;
  v_receipt_number text;
  v_subtotal numeric(14,2) := 0;
  v_discount numeric(14,2) := 0;
  v_total numeric(14,2) := 0;
  v_tendered numeric(14,2) := 0;
  v_change numeric(14,2) := 0;
  v_voucher_discount numeric(14,2) := 0;
  v_stamp_count integer := 0;
  v_stamp_ids uuid[];
  v_has_paid_qualified_service boolean := false;
  v_item_count integer := 0;
  v_voucher text;
  v_lines jsonb := '[]'::jsonb;
  v_transaction_day text := to_char(now() at time zone 'Asia/Jakarta', 'YYYYMMDD');
begin
  if not coalesce((select public.current_user_is_active_staff()), false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  if p_idempotency_key is null then raise exception 'Kunci transaksi wajib tersedia'; end if;
  perform pg_advisory_xact_lock(hashtext(p_idempotency_key::text));
  select t.* into v_existing from public.transactions t where t.idempotency_key = p_idempotency_key;
  if found then
    select r.id, r.receipt_number into v_receipt_id, v_receipt_number from public.receipts r where r.transaction_id = v_existing.id;
    return jsonb_build_object('transaction_id',v_existing.id,'transaction_number',v_existing.transaction_number,'receipt_id',v_receipt_id,'receipt_number',v_receipt_number,'subtotal',v_existing.subtotal,'discount',v_existing.discount,'total',v_existing.total,'amount_tendered',v_existing.amount_tendered,'change',v_existing.change_due,'paid_at',v_existing.paid_at,'replayed',true);
  end if;
  if p_payment_method is null or p_payment_method not in ('cash','qris','bank_transfer') then raise exception 'Metode pembayaran tidak valid'; end if;
  if p_service_ids is null then p_service_ids := array[]::uuid[]; end if;
  if p_product_items is null then p_product_items := '[]'::jsonb; end if;
  if jsonb_typeof(p_product_items) <> 'array' then raise exception 'Daftar produk tidak valid'; end if;
  if cardinality(p_service_ids) <> (select count(distinct x) from unnest(p_service_ids) x) then raise exception 'Layanan yang sama tidak boleh dimasukkan berulang'; end if;

  if p_customer_id is not null then
    select c.* into v_customer from public.customers c where c.id = p_customer_id for update;
    if not found then raise exception 'Pelanggan tidak ditemukan'; end if;
  elsif coalesce(p_redeem_reward, false) or nullif(trim(coalesce(p_voucher_code,'')), '') is not null then
    raise exception 'Pilih pelanggan untuk menggunakan reward atau voucher';
  end if;

  if p_barber_id is not null and not exists(select 1 from public.barbers b where b.id=p_barber_id and b.is_active) then
    raise exception 'Barber tidak aktif atau tidak ditemukan';
  end if;

  if cardinality(p_service_ids) > 0 then
    for v_service in select s.* from public.services s where s.id = any(p_service_ids) and s.is_active order by s.id loop
      v_subtotal := v_subtotal + v_service.price;
      v_item_count := v_item_count + 1;
      v_lines := v_lines || jsonb_build_array(jsonb_build_object(
        'item_type','service','item_id',v_service.id,'description',v_service.name,
        'quantity',1,'unit_price',v_service.price,'unit_cost',0,'barber_id',p_barber_id
      ));
      if v_service.earns_loyalty_stamp and v_service.price > 0 then v_has_paid_qualified_service := true; end if;
    end loop;
    if v_item_count <> cardinality(p_service_ids) then raise exception 'Ada layanan tidak aktif atau tidak ditemukan'; end if;
  end if;

  for v_product in
    select x.product_id, sum(x.quantity)::integer as quantity
    from jsonb_to_recordset(p_product_items) as x(product_id uuid, quantity integer)
    group by x.product_id order by x.product_id
  loop
    if v_product.product_id is null or v_product.quantity is null or v_product.quantity < 1 or v_product.quantity > 1000 then
      raise exception 'Jumlah produk tidak valid';
    end if;
    select p.* into v_product_data from public.products p
    where p.id=v_product.product_id and p.is_active and p.stock_quantity>=v_product.quantity
    for update;
    if not found then raise exception 'Produk tidak aktif atau stok tidak mencukupi'; end if;
    update public.products p
    set stock_quantity = p.stock_quantity - v_product.quantity, updated_at = now()
    where p.id = v_product_data.id;
    v_subtotal := v_subtotal + v_product_data.selling_price * v_product.quantity;
    v_item_count := v_item_count + 1;
    v_lines := v_lines || jsonb_build_array(jsonb_build_object(
      'item_type','product','item_id',v_product_data.id,'description',v_product_data.name,
      'quantity',v_product.quantity,'unit_price',v_product_data.selling_price,
      'unit_cost',v_product_data.purchase_price,'barber_id',p_barber_id
    ));
  end loop;
  if v_item_count = 0 then raise exception 'Pilih setidaknya satu layanan atau produk'; end if;

  if coalesce(p_redeem_reward,false) then
    select m.* into v_membership from public.memberships m where m.customer_id=p_customer_id and m.status='active' for update;
    if not found then raise exception 'Pelanggan belum memiliki membership aktif'; end if;
    select r.* into v_reward from public.loyalty_rewards r
    where r.is_active and r.required_stamps=5
      and exists(select 1 from public.services s where s.id=r.reward_service_id and s.earns_loyalty_stamp)
    order by r.created_at limit 1;
    if not found then raise exception 'Aturan reward 5 stamp belum dikonfigurasi'; end if;
    if v_reward.reward_service_id is null or not (v_reward.reward_service_id = any(p_service_ids)) then raise exception 'Pilih layanan potong rambut yang memenuhi syarat untuk menggunakan reward'; end if;
    select array_agg(s.id order by s.created_at,s.id),count(*)::integer into v_stamp_ids,v_stamp_count
    from (
      select ls.id,ls.created_at from public.loyalty_stamps ls
      where ls.membership_id=v_membership.id and ls.is_valid
      order by ls.created_at,ls.id limit v_reward.required_stamps
      for update
    ) s;
    if v_stamp_count < v_reward.required_stamps then raise exception 'Stamp belum cukup untuk menukar reward'; end if;
    update public.loyalty_stamps set is_valid=false where id=any(v_stamp_ids);
    v_subtotal := v_subtotal - (select s.price from public.services s where s.id=v_reward.reward_service_id);
    select coalesce(jsonb_agg(
      case
        when e.line->>'item_type'='service' and (e.line->>'item_id')::uuid=v_reward.reward_service_id then
          e.line || jsonb_build_object('unit_price',0,'description',(e.line->>'description')||' (Gratis - reward member)')
        else e.line
      end order by e.ordinality
    ),'[]'::jsonb) into v_lines
    from jsonb_array_elements(v_lines) with ordinality as e(line,ordinality);
  end if;

  v_discount := greatest(coalesce(p_discount,0),0);
  if p_discount is not null and p_discount<0 then raise exception 'Diskon tidak boleh negatif'; end if;
  if v_discount > v_subtotal then raise exception 'Diskon tidak boleh melebihi subtotal'; end if;
  if v_discount > 0
    and coalesce((select public.current_app_role())::text,'') <> 'owner'
    and v_discount > round(v_subtotal * 0.15,0) then
    raise exception 'Diskon manual admin staf maksimal 15%%';
  end if;
  v_voucher := nullif(upper(trim(coalesce(p_voucher_code,''))), '');
  if v_voucher is not null then
    select p.* into v_promotion from public.promotions p
    where p.code=v_voucher and p.is_active and now() between p.starts_at and p.ends_at
    for update;
    if not found then raise exception 'Voucher tidak aktif atau sudah kedaluwarsa'; end if;
    if v_subtotal < v_promotion.minimum_transaction then raise exception 'Subtotal belum memenuhi minimum voucher'; end if;
    if v_promotion.max_redemptions is not null and (select count(*) from public.promotion_redemptions r where r.promotion_id=v_promotion.id and not r.is_refunded) >= v_promotion.max_redemptions then
      raise exception 'Kuota voucher sudah habis';
    end if;
    if (select count(*) from public.promotion_redemptions r where r.promotion_id=v_promotion.id and r.customer_id=p_customer_id and not r.is_refunded) >= v_promotion.per_customer_limit then
      raise exception 'Batas penggunaan voucher pelanggan sudah tercapai';
    end if;
    if v_promotion.discount_type='percent' then
      v_voucher_discount := round(v_subtotal * v_promotion.discount_value / 100,0);
    else
      v_voucher_discount := v_promotion.discount_value;
    end if;
    v_voucher_discount := least(v_voucher_discount,v_subtotal-v_discount);
    v_discount := v_discount+v_voucher_discount;
  end if;
  v_total := greatest(v_subtotal-v_discount,0);
  v_tendered := coalesce(p_amount_tendered,0);
  if v_tendered < v_total then raise exception 'Jumlah pembayaran kurang dari total transaksi'; end if;
  if p_payment_method <> 'cash' and v_tendered <> v_total then raise exception 'Pembayaran non-tunai harus sama dengan total'; end if;
  v_change := case when p_payment_method='cash' then v_tendered-v_total else 0 end;

  v_transaction_number := 'GS-'||v_transaction_day||'-'||lpad(nextval('public.transaction_number_seq')::text,8,'0');
  insert into public.transactions(transaction_number,idempotency_key,voucher_code,customer_id,cashier_id,subtotal,discount,total,amount_tendered,change_due,status,paid_at)
  values(v_transaction_number,p_idempotency_key,v_voucher,p_customer_id,auth.uid(),v_subtotal,v_discount,v_total,v_tendered,v_change,'completed',now())
  returning id into v_transaction_id;

  insert into public.transaction_items(transaction_id,item_type,item_id,description,quantity,unit_price,unit_cost,barber_id)
  select v_transaction_id,x.item_type,x.item_id,x.description,x.quantity,x.unit_price,x.unit_cost,x.barber_id
  from jsonb_to_recordset(v_lines) as x(item_type text,item_id uuid,description text,quantity integer,unit_price numeric,unit_cost numeric,barber_id uuid);
  insert into public.payments(transaction_id,method,amount) values(v_transaction_id,p_payment_method,v_total);
  insert into public.receipts(transaction_id,receipt_number) values(v_transaction_id,v_transaction_number)
  returning id,receipt_number into v_receipt_id,v_receipt_number;

  for v_product in
    select ti.item_id,ti.quantity from public.transaction_items ti
    where ti.transaction_id=v_transaction_id and ti.item_type='product'
  loop
    insert into public.inventory_movements(product_id,movement_type,quantity,note,created_by)
    values(v_product.item_id,'sale',-v_product.quantity,'POS '||v_transaction_number,auth.uid());
  end loop;

  if v_voucher is not null then
    insert into public.promotion_redemptions(promotion_id,customer_id,transaction_id,discount_amount)
    values(v_promotion.id,p_customer_id,v_transaction_id,v_voucher_discount);
  end if;

  if coalesce(p_redeem_reward,false) then
    insert into public.transaction_loyalty_redemptions(transaction_id,membership_id,reward_id,stamp_ids)
    values(v_transaction_id,v_membership.id,v_reward.id,v_stamp_ids);
    insert into public.reward_redemptions(membership_id,reward_id,transaction_id)
    values(v_membership.id,v_reward.id,v_transaction_id);
  end if;

  if p_customer_id is not null and v_has_paid_qualified_service and not coalesce(p_redeem_reward,false) then
    insert into public.memberships(customer_id) values(p_customer_id)
    on conflict(customer_id) do nothing;
    insert into public.loyalty_stamps(membership_id,transaction_id,is_valid)
    select m.id,v_transaction_id,true from public.memberships m
    where m.customer_id=p_customer_id and m.status='active';
  end if;

  insert into public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
  values(auth.uid(),'pos.completed','transaction',v_transaction_id::text,jsonb_build_object('transaction_number',v_transaction_number,'total',v_total,'payment_method',p_payment_method));

  return jsonb_build_object(
    'transaction_id',v_transaction_id,'transaction_number',v_transaction_number,
    'receipt_id',v_receipt_id,'receipt_number',v_receipt_number,
    'subtotal',v_subtotal,'discount',v_discount,'total',v_total,
    'amount_tendered',v_tendered,'change',v_change,'paid_at',now(),'replayed',false
  );
end;
$$;

create or replace function public.admin_refund_transaction(p_transaction_id uuid,p_reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_transaction public.transactions%rowtype;
  v_refund_number text;
  v_reason text := left(trim(coalesce(p_reason,'')),500);
  v_item record;
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Refund hanya dapat dilakukan oleh Super Admin'; end if;
  if char_length(v_reason)<5 then raise exception 'Alasan refund minimal 5 karakter'; end if;
  select t.* into v_transaction from public.transactions t where t.id=p_transaction_id for update;
  if not found then raise exception 'Transaksi tidak ditemukan'; end if;
  if v_transaction.status <> 'completed' then raise exception 'Hanya transaksi selesai yang dapat di-refund'; end if;

  for v_item in select ti.item_id,ti.quantity from public.transaction_items ti where ti.transaction_id=p_transaction_id and ti.item_type='product' order by ti.item_id loop
    update public.products set stock_quantity=stock_quantity+v_item.quantity,updated_at=now() where id=v_item.item_id;
    insert into public.inventory_movements(product_id,movement_type,quantity,note,created_by)
    values(v_item.item_id,'refund',v_item.quantity,'Refund '||v_transaction.transaction_number,auth.uid());
  end loop;

  update public.loyalty_stamps set is_valid=false
  where transaction_id=p_transaction_id and is_valid;
  update public.loyalty_stamps set is_valid=true
  where id in (select unnest(r.stamp_ids) from public.transaction_loyalty_redemptions r where r.transaction_id=p_transaction_id);
  update public.promotion_redemptions set is_refunded=true where transaction_id=p_transaction_id;

  update public.transactions set status='refunded',updated_at=now() where id=p_transaction_id;
  v_refund_number := 'RF-'||to_char(now() at time zone 'Asia/Jakarta','YYYYMMDD')||'-'||lpad(nextval('public.transaction_number_seq')::text,8,'0');
  insert into public.transaction_refunds(transaction_id,refund_number,amount,reason,refunded_by)
  values(p_transaction_id,v_refund_number,v_transaction.total,v_reason,auth.uid());
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,before_data,after_data)
  values(auth.uid(),'pos.refunded','transaction',p_transaction_id::text,jsonb_build_object('status','completed'),jsonb_build_object('status','refunded','refund_number',v_refund_number,'reason',v_reason));
  return jsonb_build_object('refund_number',v_refund_number,'amount',v_transaction.total);
end;
$$;

create or replace function public.admin_inventory_products()
returns table(id uuid,name text,sku text,category text,unit text,purchase_price numeric,selling_price numeric,stock_quantity integer,minimum_stock integer,is_active boolean)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not coalesce((select public.current_user_is_active_staff()),false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  return query select p.id,p.name,p.sku,p.category,p.unit,p.purchase_price,p.selling_price,p.stock_quantity,p.minimum_stock,p.is_active
  from public.products p order by p.is_active desc,p.name;
end;
$$;

create or replace function public.admin_save_product(
  p_product_id uuid,p_name text,p_sku text,p_category text,p_unit text,
  p_purchase_price numeric,p_selling_price numeric,p_minimum_stock integer,p_is_active boolean
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_name text:=trim(regexp_replace(coalesce(p_name,''),'\s+',' ','g'));
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Data dan harga produk hanya dapat dikelola Super Admin'; end if;
  if char_length(v_name)<2 or char_length(v_name)>100 then raise exception 'Nama produk tidak valid'; end if;
  if p_purchase_price<0 or p_selling_price<0 or p_minimum_stock<0 then raise exception 'Harga dan stok minimum tidak boleh negatif'; end if;
  if p_product_id is null then
    insert into public.products(name,sku,category,unit,purchase_price,selling_price,minimum_stock,is_active)
    values(v_name,nullif(trim(coalesce(p_sku,'')),''),coalesce(nullif(trim(p_category),''),'Umum'),coalesce(nullif(trim(p_unit),''),'pcs'),p_purchase_price,p_selling_price,p_minimum_stock,coalesce(p_is_active,true))
    returning id into v_id;
  else
    update public.products set name=v_name,sku=nullif(trim(coalesce(p_sku,'')),''),category=coalesce(nullif(trim(p_category),''),'Umum'),
      unit=coalesce(nullif(trim(p_unit),''),'pcs'),purchase_price=p_purchase_price,selling_price=p_selling_price,
      minimum_stock=p_minimum_stock,is_active=coalesce(p_is_active,true),updated_at=now()
    where id=p_product_id returning id into v_id;
    if not found then raise exception 'Produk tidak ditemukan'; end if;
  end if;
  return v_id;
exception when unique_violation then raise exception 'SKU sudah digunakan produk lain';
end;
$$;

create or replace function public.admin_adjust_inventory(p_product_id uuid,p_quantity integer,p_movement_type text,p_note text)
returns integer language plpgsql security definer set search_path=''
as $$
declare v_stock integer; v_next integer;
begin
  if not coalesce((select public.current_user_is_active_staff()),false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  if p_quantity is null or p_quantity=0 or p_movement_type not in ('adjustment','damaged','expired') then raise exception 'Penyesuaian stok tidak valid'; end if;
  if char_length(trim(coalesce(p_note,'')))<3 then raise exception 'Catatan penyesuaian minimal 3 karakter'; end if;
  if p_movement_type in ('damaged','expired') and p_quantity>0 then raise exception 'Barang rusak atau kedaluwarsa harus mengurangi stok'; end if;
  update public.products set stock_quantity=stock_quantity+p_quantity,updated_at=now()
  where id=p_product_id and stock_quantity+p_quantity>=0 returning stock_quantity into v_next;
  if not found then raise exception 'Produk tidak ditemukan atau stok tidak mencukupi'; end if;
  insert into public.inventory_movements(product_id,movement_type,quantity,note,created_by)
  values(p_product_id,p_movement_type,p_quantity,left(trim(coalesce(p_note,'')),500),auth.uid());
  return v_next;
end;
$$;

create or replace function public.admin_save_supplier(p_id uuid,p_name text,p_phone text,p_email text,p_notes text)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid;
begin
  if not coalesce((select public.current_user_is_active_staff()),false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  if char_length(trim(coalesce(p_name,'')))<2 or char_length(trim(p_name))>120 then raise exception 'Nama pemasok tidak valid'; end if;
  if nullif(trim(coalesce(p_email,'')),'') is not null and trim(p_email) !~* '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then raise exception 'Format email pemasok tidak valid'; end if;
  if p_id is null then
    insert into public.suppliers(name,phone,email,notes)
    values(trim(p_name),nullif(trim(coalesce(p_phone,'')),''),nullif(lower(trim(coalesce(p_email,''))),''),left(trim(coalesce(p_notes,'')),500))
    returning id into v_id;
  else
    update public.suppliers set name=trim(p_name),phone=nullif(trim(coalesce(p_phone,'')),''),email=nullif(lower(trim(coalesce(p_email,''))),''),notes=left(trim(coalesce(p_notes,'')),500),updated_at=now()
    where id=p_id returning id into v_id;
    if not found then raise exception 'Pemasok tidak ditemukan'; end if;
  end if;
  return v_id;
end;
$$;

create or replace function public.admin_list_suppliers()
returns table(id uuid,name text,phone text,email text,is_active boolean)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not coalesce((select public.current_user_is_active_staff()),false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  return query select s.id,s.name,s.phone,s.email,s.is_active from public.suppliers s where s.is_active order by s.name;
end;
$$;

create or replace function public.admin_receive_purchase(p_supplier_id uuid,p_notes text,p_items jsonb)
returns jsonb language plpgsql security definer set search_path=''
as $$
declare
  v_item record;
  v_product public.products%rowtype;
  v_purchase_id uuid;
  v_purchase_number text;
  v_total numeric(14,2):=0;
  v_count integer:=0;
begin
  if not coalesce((select public.current_user_is_active_staff()),false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' then raise exception 'Daftar barang pembelian tidak valid'; end if;
  if p_supplier_id is not null and not exists(select 1 from public.suppliers s where s.id=p_supplier_id and s.is_active) then raise exception 'Pemasok tidak ditemukan'; end if;
  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity,max(x.unit_cost)::numeric unit_cost,count(distinct x.unit_cost) cost_count
    from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer,unit_cost numeric)
    group by x.product_id order by x.product_id
  loop
    if v_item.product_id is null or v_item.quantity is null or v_item.quantity<1 or v_item.quantity>10000 or v_item.unit_cost is null or v_item.unit_cost<0 or v_item.cost_count<>1 then
      raise exception 'Jumlah atau harga modal barang pembelian tidak valid';
    end if;
    select p.* into v_product from public.products p where p.id=v_item.product_id and p.is_active for update;
    if not found then raise exception 'Produk pembelian tidak aktif atau tidak ditemukan'; end if;
    v_total:=v_total+(v_item.quantity*v_item.unit_cost);
    v_count:=v_count+1;
  end loop;
  if v_count=0 then raise exception 'Pilih setidaknya satu produk'; end if;

  v_purchase_number:='PO-'||to_char(now() at time zone 'Asia/Jakarta','YYYYMMDD')||'-'||lpad(nextval('public.transaction_number_seq')::text,8,'0');
  insert into public.purchases(purchase_number,supplier_id,total,notes,created_by)
  values(v_purchase_number,p_supplier_id,v_total,left(trim(coalesce(p_notes,'')),500),auth.uid())
  returning id into v_purchase_id;

  for v_item in
    select x.product_id,sum(x.quantity)::integer quantity,max(x.unit_cost)::numeric unit_cost
    from jsonb_to_recordset(p_items) as x(product_id uuid,quantity integer,unit_cost numeric)
    group by x.product_id order by x.product_id
  loop
    select p.* into v_product from public.products p where p.id=v_item.product_id for update;
    insert into public.purchase_items(purchase_id,product_id,quantity,unit_cost)
    values(v_purchase_id,v_item.product_id,v_item.quantity,v_item.unit_cost);
    update public.products p
    set purchase_price=case
          when p.stock_quantity+v_item.quantity=0 then v_item.unit_cost
          else round(((p.stock_quantity*p.purchase_price)+(v_item.quantity*v_item.unit_cost))/(p.stock_quantity+v_item.quantity),2)
        end,
        stock_quantity=p.stock_quantity+v_item.quantity,updated_at=now()
    where p.id=v_item.product_id;
    insert into public.inventory_movements(product_id,movement_type,quantity,note,created_by)
    values(v_item.product_id,'purchase',v_item.quantity,'Pembelian '||v_purchase_number,auth.uid());
  end loop;
  insert into public.audit_logs(actor_id,action,entity_type,entity_id,after_data)
  values(auth.uid(),'inventory.purchase_received','purchase',v_purchase_id::text,jsonb_build_object('purchase_number',v_purchase_number,'total',v_total));
  return jsonb_build_object('purchase_id',v_purchase_id,'purchase_number',v_purchase_number,'total',v_total);
end;
$$;

create or replace function public.admin_create_expense(p_category text,p_description text,p_amount numeric,p_expense_date date)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_category text:=trim(regexp_replace(coalesce(p_category,''),'\s+',' ','g'));
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Pencatatan pengeluaran hanya untuk Super Admin'; end if;
  if char_length(v_category)<2 or char_length(v_category)>80 or p_amount is null or p_amount<=0 or p_expense_date is null then raise exception 'Data pengeluaran tidak valid'; end if;
  insert into public.expenses(category,description,amount,expense_date,created_by)
  values(v_category,left(trim(coalesce(p_description,'')),500),p_amount,p_expense_date,auth.uid()) returning id into v_id;
  return v_id;
end;
$$;

create or replace function public.admin_list_expenses(p_start date,p_end date)
returns table(id uuid,category text,description text,amount numeric,expense_date date)
language plpgsql stable security definer set search_path=''
as $$
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Data pengeluaran hanya dapat dilihat Super Admin'; end if;
  if p_start is null or p_end is null or p_end<p_start or p_end-p_start>366 then raise exception 'Rentang pengeluaran tidak valid'; end if;
  return query select e.id,e.category,e.description,e.amount,e.expense_date from public.expenses e where e.expense_date between p_start and p_end order by e.expense_date desc,e.created_at desc;
end;
$$;

create or replace function public.admin_business_report(p_start timestamptz,p_end timestamptz)
returns jsonb language plpgsql stable security definer set search_path=''
as $$
declare v_result jsonb;
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Laporan keuangan hanya untuk Super Admin'; end if;
  if p_start is null or p_end is null or p_end<=p_start or p_end-p_start>interval '366 days' then raise exception 'Rentang laporan tidak valid'; end if;
  select jsonb_build_object(
    'revenue',coalesce(sum(t.total) filter(where t.status='completed'),0),
    'transactions',count(t.id) filter(where t.status='completed'),
    'refunds',coalesce((select sum(r.amount) from public.transaction_refunds r where r.created_at>=p_start and r.created_at<p_end),0),
    'cost_of_goods',coalesce((select sum(ti.quantity*ti.unit_cost) from public.transaction_items ti join public.transactions tx on tx.id=ti.transaction_id where ti.item_type='product' and tx.status='completed' and tx.created_at>=p_start and tx.created_at<p_end),0),
    'expenses',coalesce((select sum(e.amount) from public.expenses e where e.expense_date >= (p_start at time zone 'Asia/Jakarta')::date and e.expense_date < (p_end at time zone 'Asia/Jakarta')::date),0),
    'cash_in',coalesce((select sum(p.amount) from public.payments p join public.transactions tx on tx.id=p.transaction_id where tx.status in ('completed','refunded') and tx.created_at>=p_start and tx.created_at<p_end),0),
    'payment_methods',coalesce((select jsonb_object_agg(method,amount) from (select p.method,sum(p.amount) amount from public.payments p join public.transactions tx on tx.id=p.transaction_id where tx.status='completed' and tx.created_at>=p_start and tx.created_at<p_end group by p.method) pm),'{}'::jsonb),
    'top_services',coalesce((select jsonb_agg(jsonb_build_object('name',name,'quantity',quantity) order by quantity desc) from (select ti.description name,sum(ti.quantity)::bigint quantity from public.transaction_items ti join public.transactions tx on tx.id=ti.transaction_id where ti.item_type='service' and tx.status='completed' and tx.created_at>=p_start and tx.created_at<p_end group by ti.description order by sum(ti.quantity) desc limit 5) top),'[]'::jsonb),
    'top_products',coalesce((select jsonb_agg(jsonb_build_object('name',name,'quantity',quantity) order by quantity desc) from (select ti.description name,sum(ti.quantity)::bigint quantity from public.transaction_items ti join public.transactions tx on tx.id=ti.transaction_id where ti.item_type='product' and tx.status='completed' and tx.created_at>=p_start and tx.created_at<p_end group by ti.description order by sum(ti.quantity) desc limit 5) top),'[]'::jsonb)
  ) into v_result
  from public.transactions t
  where t.created_at>=p_start and t.created_at<p_end;
  v_result := v_result || jsonb_build_object(
    'gross_profit',coalesce((v_result->>'revenue')::numeric,0)-coalesce((v_result->>'cost_of_goods')::numeric,0),
    'estimated_net_profit',coalesce((v_result->>'revenue')::numeric,0)-coalesce((v_result->>'cost_of_goods')::numeric,0)-coalesce((v_result->>'expenses')::numeric,0),
    'net_cash_flow',coalesce((v_result->>'cash_in')::numeric,0)-coalesce((v_result->>'refunds')::numeric,0)-coalesce((v_result->>'expenses')::numeric,0)
  );
  return v_result;
end;
$$;

create or replace function public.admin_inventory_report()
returns jsonb language plpgsql stable security definer set search_path=''
as $$
begin
  if not coalesce((select public.current_user_is_active_staff()),false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  return jsonb_build_object(
    'product_count',(select count(*) from public.products where is_active),
    'low_stock',coalesce((select jsonb_agg(jsonb_build_object('id',id,'name',name,'sku',sku,'stock',stock_quantity,'minimum_stock',minimum_stock) order by stock_quantity,name) from public.products where is_active and stock_quantity<=minimum_stock),'[]'::jsonb),
    'inventory_value',coalesce((select sum(stock_quantity*purchase_price) from public.products where is_active),0),
    'recent_movements',coalesce((select jsonb_agg(jsonb_build_object('product',p.name,'type',m.movement_type,'quantity',m.quantity,'note',m.note,'created_at',m.created_at) order by m.created_at desc) from (select * from public.inventory_movements order by created_at desc limit 30) m join public.products p on p.id=m.product_id),'[]'::jsonb)
  );
end;
$$;

create or replace function public.admin_save_promotion(
  p_id uuid,p_code text,p_name text,p_discount_type text,p_discount_value numeric,
  p_minimum_transaction numeric,p_max_redemptions integer,p_per_customer_limit integer,
  p_starts_at timestamptz,p_ends_at timestamptz,p_is_active boolean,p_terms text
)
returns uuid language plpgsql security definer set search_path=''
as $$
declare v_id uuid; v_code text:=upper(trim(coalesce(p_code,'')));
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Promosi hanya dapat dikelola Super Admin'; end if;
  if v_code !~ '^[A-Z0-9][A-Z0-9_-]{2,31}$' or char_length(trim(coalesce(p_name,'')))<2 then raise exception 'Kode dan nama promosi tidak valid'; end if;
  if p_discount_type not in ('fixed','percent') or p_discount_value<=0 or p_minimum_transaction<0 or p_per_customer_limit<1 or p_starts_at is null or p_ends_at<=p_starts_at then raise exception 'Aturan promosi tidak valid'; end if;
  if p_discount_type='percent' and p_discount_value>100 then raise exception 'Diskon persentase maksimal 100 persen'; end if;
  if p_id is null then
    insert into public.promotions(code,name,discount_type,discount_value,minimum_transaction,max_redemptions,per_customer_limit,starts_at,ends_at,is_active,terms,created_by)
    values(v_code,trim(p_name),p_discount_type,p_discount_value,p_minimum_transaction,p_max_redemptions,p_per_customer_limit,p_starts_at,p_ends_at,coalesce(p_is_active,true),left(trim(coalesce(p_terms,'')),1000),auth.uid()) returning id into v_id;
  else
    update public.promotions set code=v_code,name=trim(p_name),discount_type=p_discount_type,discount_value=p_discount_value,
      minimum_transaction=p_minimum_transaction,max_redemptions=p_max_redemptions,per_customer_limit=p_per_customer_limit,
      starts_at=p_starts_at,ends_at=p_ends_at,is_active=coalesce(p_is_active,true),terms=left(trim(coalesce(p_terms,'')),1000),updated_at=now()
    where id=p_id returning id into v_id;
    if not found then raise exception 'Promosi tidak ditemukan'; end if;
  end if;
  return v_id;
exception when unique_violation then raise exception 'Kode voucher sudah digunakan';
end;
$$;

create or replace function public.admin_list_promotions()
returns table(id uuid,code text,name text,discount_type text,discount_value numeric,minimum_transaction numeric,starts_at timestamptz,ends_at timestamptz,is_active boolean,redemptions bigint)
language plpgsql stable security definer set search_path=''
as $$
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Promosi hanya dapat dikelola Super Admin'; end if;
  return query select p.id,p.code,p.name,p.discount_type,p.discount_value,p.minimum_transaction,p.starts_at,p.ends_at,p.is_active,count(r.id) filter(where not r.is_refunded)
  from public.promotions p left join public.promotion_redemptions r on r.promotion_id=p.id
  group by p.id order by p.created_at desc;
end;
$$;

create or replace function public.admin_prepare_campaign(p_name text,p_segment text,p_message_template text)
returns table(campaign_id uuid,customer_id uuid,customer_name text,phone text,member_code text)
language plpgsql security definer set search_path=''
as $$
declare v_campaign_id uuid;
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Campaign hanya dapat disiapkan Super Admin'; end if;
  if char_length(trim(coalesce(p_name,'')))<2 or char_length(trim(coalesce(p_message_template,'')))<5 then raise exception 'Nama campaign atau pesan tidak valid'; end if;
  if p_segment not in ('all','new','active','loyal','vip','inactive','lost','birthday') then raise exception 'Segment campaign tidak valid'; end if;
  insert into public.marketing_campaigns(name,segment,message_template,recipient_count,prepared_by)
  values(trim(p_name),p_segment,left(trim(p_message_template),1000),0,auth.uid()) returning id into v_campaign_id;
  with customer_stats as (
    select c.id,
      count(t.id) filter(where t.status='completed')::bigint as transactions,
      max(t.created_at) filter(where t.status='completed') as last_seen
    from public.customers c
    left join public.transactions t on t.customer_id=c.id
    group by c.id
  ), classified as (
    select c.id,
      case
        when c.birth_date is not null
          and extract(month from c.birth_date)=extract(month from (now() at time zone 'Asia/Jakarta')::date)
          and extract(day from c.birth_date)=extract(day from (now() at time zone 'Asia/Jakarta')::date) then 'birthday'
        when s.transactions>=20 then 'vip'
        when s.transactions>=5 and s.last_seen>=now()-interval '90 days' then 'loyal'
        when s.transactions>0 and s.last_seen>=now()-interval '60 days' then 'active'
        when s.last_seen<now()-interval '90 days' then 'lost'
        when s.last_seen<now()-interval '30 days' then 'inactive'
        else 'new'
      end as customer_segment
    from public.customers c
    join customer_stats s on s.id=c.id
    where c.marketing_opt_in and c.phone is not null
  )
  insert into public.marketing_campaign_recipients(campaign_id,customer_id)
  select v_campaign_id,c.id from classified c
  where p_segment='all' or c.customer_segment=p_segment;
  update public.marketing_campaigns set recipient_count=(select count(*) from public.marketing_campaign_recipients where campaign_id=v_campaign_id) where id=v_campaign_id;
  return query select v_campaign_id,c.id,c.full_name,c.phone,c.member_code
  from public.marketing_campaign_recipients r join public.customers c on c.id=r.customer_id
  where r.campaign_id=v_campaign_id order by c.full_name;
end;
$$;

create or replace function public.admin_mark_campaign_chat_opened(p_campaign_id uuid,p_customer_id uuid)
returns boolean language plpgsql security definer set search_path=''
as $$
begin
  if coalesce((select public.current_app_role())::text,'') <> 'owner' then raise exception 'Campaign hanya dapat dikelola Super Admin'; end if;
  update public.marketing_campaign_recipients r set chat_opened_at=now()
  from public.customers c
  where r.campaign_id=p_campaign_id and r.customer_id=p_customer_id
    and c.id=r.customer_id and c.marketing_opt_in;
  return found;
end;
$$;

create or replace function public.admin_list_transactions(p_start timestamptz,p_end timestamptz,p_search text default null,p_limit integer default 50)
returns table(id uuid,transaction_number text,customer_name text,total numeric,status text,payment_method text,created_at timestamptz,refund_number text)
language plpgsql stable security definer set search_path=''
as $$
begin
  if not coalesce((select public.current_user_is_active_staff()),false) then raise exception 'Akses hanya untuk staf aktif'; end if;
  if p_start is null or p_end is null or p_end<=p_start or p_end-p_start>interval '93 days' then raise exception 'Rentang transaksi tidak valid'; end if;
  return query
  select t.id,t.transaction_number,coalesce(c.full_name,'Pelanggan umum'),t.total,t.status,
    (select p.method from public.payments p where p.transaction_id=t.id order by p.created_at limit 1),
    t.created_at,r.refund_number
  from public.transactions t
  left join public.customers c on c.id=t.customer_id
  left join public.transaction_refunds r on r.transaction_id=t.id
  where t.created_at>=p_start and t.created_at<p_end
    and (coalesce(trim(p_search),'')='' or t.transaction_number ilike '%'||trim(p_search)||'%' or coalesce(c.full_name,'') ilike '%'||trim(p_search)||'%')
  order by t.created_at desc
  limit greatest(1,least(coalesce(p_limit,50),100));
end;
$$;

revoke all on function public.admin_create_customer(text,text,text,date,boolean) from public,anon;
revoke all on function public.admin_search_customers(text,text,integer,integer) from public,anon;
revoke all on function public.admin_update_customer(uuid,text,text,text,date,text,boolean) from public,anon;
revoke all on function public.pos_catalog() from public,anon;
revoke all on function public.create_pos_transaction(uuid,uuid,uuid[],jsonb,numeric,text,boolean,text,numeric,uuid) from public,anon;
revoke all on function public.admin_refund_transaction(uuid,text) from public,anon;
revoke all on function public.admin_inventory_products() from public,anon;
revoke all on function public.admin_save_product(uuid,text,text,text,text,numeric,numeric,integer,boolean) from public,anon;
revoke all on function public.admin_adjust_inventory(uuid,integer,text,text) from public,anon;
revoke all on function public.admin_save_supplier(uuid,text,text,text,text) from public,anon;
revoke all on function public.admin_list_suppliers() from public,anon;
revoke all on function public.admin_receive_purchase(uuid,text,jsonb) from public,anon;
revoke all on function public.admin_create_expense(text,text,numeric,date) from public,anon;
revoke all on function public.admin_list_expenses(date,date) from public,anon;
revoke all on function public.admin_business_report(timestamptz,timestamptz) from public,anon;
revoke all on function public.admin_inventory_report() from public,anon;
revoke all on function public.admin_save_promotion(uuid,text,text,text,numeric,numeric,integer,integer,timestamptz,timestamptz,boolean,text) from public,anon;
revoke all on function public.admin_list_promotions() from public,anon;
revoke all on function public.admin_prepare_campaign(text,text,text) from public,anon;
revoke all on function public.admin_mark_campaign_chat_opened(uuid,uuid) from public,anon;
revoke all on function public.admin_list_transactions(timestamptz,timestamptz,text,integer) from public,anon;

grant execute on function public.admin_create_customer(text,text,text,date,boolean) to authenticated;
grant execute on function public.admin_search_customers(text,text,integer,integer) to authenticated;
grant execute on function public.admin_update_customer(uuid,text,text,text,date,text,boolean) to authenticated;
grant execute on function public.pos_catalog() to authenticated;
grant execute on function public.create_pos_transaction(uuid,uuid,uuid[],jsonb,numeric,text,boolean,text,numeric,uuid) to authenticated;
grant execute on function public.admin_refund_transaction(uuid,text) to authenticated;
grant execute on function public.admin_inventory_products() to authenticated;
grant execute on function public.admin_save_product(uuid,text,text,text,text,numeric,numeric,integer,boolean) to authenticated;
grant execute on function public.admin_adjust_inventory(uuid,integer,text,text) to authenticated;
grant execute on function public.admin_save_supplier(uuid,text,text,text,text) to authenticated;
grant execute on function public.admin_list_suppliers() to authenticated;
grant execute on function public.admin_receive_purchase(uuid,text,jsonb) to authenticated;
grant execute on function public.admin_create_expense(text,text,numeric,date) to authenticated;
grant execute on function public.admin_list_expenses(date,date) to authenticated;
grant execute on function public.admin_business_report(timestamptz,timestamptz) to authenticated;
grant execute on function public.admin_inventory_report() to authenticated;
grant execute on function public.admin_save_promotion(uuid,text,text,text,numeric,numeric,integer,integer,timestamptz,timestamptz,boolean,text) to authenticated;
grant execute on function public.admin_list_promotions() to authenticated;
grant execute on function public.admin_prepare_campaign(text,text,text) to authenticated;
grant execute on function public.admin_mark_campaign_chat_opened(uuid,uuid) to authenticated;
grant execute on function public.admin_list_transactions(timestamptz,timestamptz,text,integer) to authenticated;
