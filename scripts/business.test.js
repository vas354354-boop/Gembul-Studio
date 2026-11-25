const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const migration = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261124030000_business_operations.sql'), 'utf8');
const signupFix = fs.readFileSync(path.join(root, 'supabase', 'migrations', '20261124040000_fix_customer_signup_phone_conflicts.sql'), 'utf8');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');

test('checkout is idempotent and all transaction writes are server-side', () => {
  assert.match(migration, /idempotency_key uuid/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /where t\.idempotency_key = p_idempotency_key/);
  assert.match(migration, /create or replace function public\.create_pos_transaction/);
  assert.match(migration, /insert into public\.transactions/);
  assert.match(migration, /insert into public\.transaction_items/);
  assert.match(migration, /insert into public\.payments/);
  assert.match(pos, /create_pos_transaction/);
  assert.doesNotMatch(pos, /\.from\(['"]transactions['"]\)\.insert/);
  assert.match(pos, /logo\.src='\/icon-512\.png'/);
  assert.match(pos, /receipt-items/);
  assert.match(pos, /receipt-status/);
  assert.match(pos, /@page\{size:auto;margin:5mm\}/);
});

test('checkout protects pricing, stock, loyalty, promotions, and payment invariants', () => {
  for (const expression of [
    /from public\.services s where s\.id = any\(p_service_ids\) and s\.is_active/,
    /for update/,
    /stock_quantity>=v_product\.quantity/,
    /insert into public\.inventory_movements/,
    /v_discount > v_subtotal/,
    /p_payment_method <> 'cash' and v_tendered <> v_total/,
    /v_voucher_discount/,
    /insert into public\.loyalty_stamps/,
    /transaction_loyalty_redemptions/
  ]) {
    assert.match(migration, expression);
  }
});

test('full refunds require owner authorization and restore inventory and earned stamps', () => {
  const refund = migration.slice(migration.indexOf('create or replace function public.admin_refund_transaction'), migration.indexOf('create or replace function public.admin_inventory_products'));
  assert.match(refund, /current_app_role\(\).*owner/);
  assert.match(refund, /status <> 'completed'/);
  assert.match(refund, /movement_type,quantity,note,created_by\).*values\(v_item\.item_id,'refund',v_item\.quantity/s);
  assert.match(refund, /set is_valid=false/);
  assert.match(refund, /set is_valid=true/);
  assert.match(refund, /set status='refunded'/);
});

test('customer marketing uses opt-in and does not send messages automatically', () => {
  assert.match(migration, /marketing_opt_in boolean not null default false/);
  assert.match(migration, /where c\.marketing_opt_in and c\.phone is not null/);
  assert.match(pos, /p_marketing_opt_in:data\.get\('marketing_opt_in'\)==='on'/);
  const marketing = fs.readFileSync(path.join(root, 'promotions.html'), 'utf8');
  assert.match(marketing, /pesan perlu ditinjau dan dikirim manual/i);
  assert.match(migration, /with customer_stats as \(/);
});

test('inventory and finance preserve cost snapshots and enforce owner-only finance access', () => {
  assert.match(migration, /unit_cost numeric\(14,2\) not null default 0/);
  assert.match(migration, /purchase_price=case/);
  assert.match(migration, /admin_business_report/);
  assert.match(migration, /estimated_net_profit/);
  assert.match(migration, /Pencatatan pengeluaran hanya untuk Super Admin/);
  const finance = fs.readFileSync(path.join(root, 'finance.html'), 'utf8');
  assert.match(finance, /requireStaff\(true\)/);
});

test('new customer signups still succeed when the optional phone is already on a CRM record', () => {
  assert.match(signupFix, /create or replace function public\.handle_new_auth_user/);
  assert.match(signupFix, /exception\s+when unique_violation/i);
  assert.match(signupFix, /insert into public\.customers \(profile_id, full_name, member_code\)/);
  assert.match(signupFix, /insert into public\.memberships \(customer_id\)/);
  assert.match(signupFix, /drop trigger if exists on_auth_user_created_gembul/);
});
