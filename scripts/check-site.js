const fs = require('fs');
const path = require('path');

const root = path.resolve(__dirname, '..');
const required = ['index.html', 'account.html', 'admin.html', 'booking.html', 'barbers.html', 'pos.html', 'customers.html', 'inventory.html', 'transactions.html', 'finance.html', 'promotions.html', 'admin-tools.js', 'manifest.webmanifest', 'sw.js', 'customer-nav.js', 'capacitor.config.json', 'scripts/build-mobile.js', 'scripts/build-web.js', 'vercel.json', 'DEPLOYMENT.md', 'supabase/migrations/20261120030000_public_barber_catalog.sql', 'supabase/migrations/20261120040000_booking_queue_rpc.sql', 'supabase/migrations/20261120050000_booking_cancellation_guard.sql', 'supabase/migrations/20261123010000_cipete_booking_location.sql', 'supabase/migrations/20261123020000_cipete_booking_hours.sql', 'supabase/migrations/20261123030000_cipete_barber_management.sql', 'supabase/migrations/20261124010000_admin_dashboard_metrics.sql', 'supabase/migrations/20261124020000_admin_booking_operations.sql', 'supabase/migrations/20261124030000_business_operations.sql', 'supabase/migrations/20261124040000_fix_customer_signup_phone_conflicts.sql'];
const missing = required.filter((file) => !fs.existsSync(path.join(root, file)));
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const account = fs.readFileSync(path.join(root, 'account.html'), 'utf8');
const barbers = fs.readFileSync(path.join(root, 'barbers.html'), 'utf8');
const admin = fs.readFileSync(path.join(root, 'admin.html'), 'utf8');
const dashboardMetrics = fs.readFileSync(path.join(root, 'supabase/migrations/20261124010000_admin_dashboard_metrics.sql'), 'utf8');
const bookingOperations = fs.readFileSync(path.join(root, 'supabase/migrations/20261124020000_admin_booking_operations.sql'), 'utf8');
const businessOperations = fs.readFileSync(path.join(root, 'supabase/migrations/20261124030000_business_operations.sql'), 'utf8');
const pos = fs.readFileSync(path.join(root, 'pos.html'), 'utf8');
const customers = fs.readFileSync(path.join(root, 'customers.html'), 'utf8');
const inventory = fs.readFileSync(path.join(root, 'inventory.html'), 'utf8');
const finance = fs.readFileSync(path.join(root, 'finance.html'), 'utf8');
const promotions = fs.readFileSync(path.join(root, 'promotions.html'), 'utf8');
const transactions = fs.readFileSync(path.join(root, 'transactions.html'), 'utf8');
const serviceWorker = fs.readFileSync(path.join(root, 'sw.js'), 'utf8');
const mobileConfig = JSON.parse(fs.readFileSync(path.join(root, 'capacitor.config.json'), 'utf8'));
const deploymentConfig = JSON.parse(fs.readFileSync(path.join(root, 'vercel.json'), 'utf8'));
const config = fs.readFileSync(path.join(root, 'supabase-config.js'), 'utf8');
const booking = fs.readFileSync(path.join(root, 'booking.html'), 'utf8');
const locationMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20261123010000_cipete_booking_location.sql'), 'utf8');
const hoursMigration = fs.readFileSync(path.join(root, 'supabase/migrations/20261123020000_cipete_booking_hours.sql'), 'utf8');
const checks = {
  manifestLink: html.includes('/manifest.webmanifest'),
  serviceWorkerRegistration: html.includes("navigator.serviceWorker.register('/sw.js')"),
  websiteInstallSection: html.includes('<section id="install"') && html.includes('Tambahkan ke Layar Utama'),
  websiteInstallPrompt: html.includes('id="pwa-install"') && html.includes("addEventListener('beforeinstallprompt'") && html.includes("addEventListener('appinstalled'"),
  websiteInstallNavigation: html.includes('href="#install">Unduh Aplikasi</a>'),
  viewport: html.includes('name="viewport"'),
  existingWhatsAppBooking: html.includes('6282142168938'),
  liveServiceCatalog: html.includes("rest/v1/services?select=name,price,duration_minutes"),
  configuredSupabaseProject: config.includes('https://kzdzeuxeojarhksraqqz.supabase.co'),
  customerAccountLink: html.includes('href="/account.html"'),
  customerSignupAndLogin: account.includes('client.auth.signUp') && account.includes('client.auth.signInWithPassword'),
  passwordRecoveryFlow: account.includes('resetPasswordForEmail') && account.includes("updateUser({password:password})"),
  memberStampProgress: account.includes("from('loyalty_stamps')"),
  privateBookingHistory: account.includes("from('bookings')") && account.includes("from('queues')"),
  bookingCancellation: account.includes("rpc('cancel_own_booking'"),
  bookingLink: html.includes('href="/booking.html"'),
  bookingRpc: booking.includes('create_customer_booking'),
  cipeteMapLink: booking.includes('https://maps.app.goo.gl/1kCfFAB22MmhvFUc7'),
  cipeteBarberRestriction: locationMigration.includes("br.slug = 'cipete'") && locationMigration.includes('b.branch_id = v_branch_id'),
  cipeteBusinessHours: hoursMigration.includes("time '09:00'") && hoursMigration.includes("time '22:00'") && hoursMigration.includes("at time zone 'Asia/Jakarta'"),
  barberManagerRequiresStaffRole: barbers.includes("['owner','admin_cashier'].includes(profileResult.data.role)"),
  barberManagerUsesSecureRpc: barbers.includes("rpc('add_cipete_barber'") && barbers.includes("rpc('set_cipete_barber_active'"),
  adminAndCustomerAreasAreSeparate: account.includes("window.location.replace('/admin.html')") && admin.includes('Dashboard Admin'),
  roleAwareAdminMenu: admin.includes("profile.role==='owner'") && admin.includes("'admin_cashier'"),
  dashboardUsesServerMetrics: admin.includes("rpc('admin_dashboard_metrics'") && dashboardMetrics.includes('current_user_is_active_staff()'),
  inactiveStaffRolesAreRejected: dashboardMetrics.includes('and p.is_active = true') && dashboardMetrics.includes('create or replace function public.current_app_role()'),
  dashboardReportsOmzetNotProfit: admin.includes('Bukan laba bersih.'),
  adminBookingListUsesProtectedRpc: admin.includes("rpc('admin_list_bookings'") && bookingOperations.includes('current_user_is_active_staff()'),
  adminBookingStatusUsesProtectedRpc: admin.includes("rpc('admin_update_booking_status'") && bookingOperations.includes('for update'),
  adminBookingStatusTransitionsUpdateQueue: ['checked_in', 'completed', 'cancelled', 'no_show'].every((value) => bookingOperations.includes(`p_status = '${value}'`)),
  capacitorTargetsAndroidAndIos: mobileConfig.appId === 'com.gembul.studio' && mobileConfig.webDir === 'mobile/www',
  mobileNavigationSupportsCustomerFlows: fs.readFileSync(path.join(root, 'customer-nav.js'), 'utf8').includes('/booking.html')
    && fs.readFileSync(path.join(root, 'customer-nav.js'), 'utf8').includes('#booking-history'),
  nativeBuildDoesNotRegisterServiceWorker: html.includes('if(!isNativeApp&&'),
  adminMenuLinksBarberManagement: admin.includes('href="/barbers.html"'),
  adminMenuLinksBusinessModules: ['/pos.html','/customers.html','/inventory.html','/transactions.html','/finance.html','/promotions.html'].every((href) => admin.includes(`href="${href}"`)),
  ownerOnlyFinanceMenu: admin.includes('owner-menu') && admin.includes('link.hidden=!isOwner'),
  posUsesProtectedIdempotentRpc: pos.includes("call(context.client,'create_pos_transaction'") && pos.includes("sessionStorage.setItem('gembul-pos-pending'"),
  posProvidesFormalBrandedReceipt: pos.includes("logo.src='/icon-512.png'") && pos.includes('receipt-meta') && pos.includes('receipt-items') && pos.includes('LUNAS') && pos.includes('size:auto;margin:5mm'),
  posProvidesReceiptAndManualWhatsapp: pos.includes('window.print()') && pos.includes('Pesan tidak dikirim otomatis'),
  crmUsesProtectedFunctions: customers.includes("call(context.client,'admin_search_customers'") && customers.includes("call(context.client,'admin_update_customer'"),
  inventoryUsesProtectedFunctions: inventory.includes("call(context.client,'admin_receive_purchase'") && inventory.includes("call(context.client,'admin_adjust_inventory'"),
  financeIsOwnerOnly: finance.includes('requireStaff(true)') && businessOperations.includes('Laporan keuangan hanya untuk Super Admin'),
  promotionsAreOwnerOnlyAndOptIn: promotions.includes('requireStaff(true)') && businessOperations.includes('c.marketing_opt_in and c.phone is not null'),
  refundIsOwnerOnly: transactions.includes("call(context.client,'admin_refund_transaction'") && businessOperations.includes('Refund hanya dapat dilakukan oleh Super Admin'),
  serverEnforcesCheckoutAndRollbacks: ['pg_advisory_xact_lock','stock_quantity>=v_product.quantity','inventory_movements','transaction_loyalty_redemptions','amount_tendered','p_payment_method'].every((term) => businessOperations.includes(term)),
  businessFunctionsRestrictAnonymousAccess: businessOperations.includes('revoke all on function public.create_pos_transaction') && businessOperations.includes('grant execute on function public.create_pos_transaction'),
  serviceWorkerProtectsPrivatePages: serviceWorker.includes('const PRIVATE_PATHS = new Set([')
    && ['/account.html','/admin.html','/booking.html','/barbers.html','/pos.html','/customers.html','/inventory.html','/transactions.html','/finance.html','/promotions.html'].every((asset) => serviceWorker.includes(`'${asset}'`)),
  webDeploymentUsesStaticBuildOutput: deploymentConfig.buildCommand === 'npm run build:web' && deploymentConfig.outputDirectory === 'dist',
  webDeploymentSetsSecurityHeaders: ['X-Content-Type-Options','X-Frame-Options','Referrer-Policy','Permissions-Policy','Strict-Transport-Security'].every((name) =>
    deploymentConfig.headers.some((route) => route.headers.some((header) => header.key === name))),
  webDeploymentDisablesPrivatePageCaching: ['/account.html','/admin.html','/booking.html','/barbers.html','/pos.html','/customers.html','/inventory.html','/transactions.html','/finance.html','/promotions.html'].every((page) =>
    deploymentConfig.headers.some((route) => route.source === page && route.headers.some((header) => header.key === 'Cache-Control' && header.value.includes('no-store')))),
  customerAccountDoesNotShowAdminMenu: !account.includes('href="/barbers.html"') && !account.includes('href="/admin.html"'),
  barberManagerCanLogout: barbers.includes('id="logout"') && barbers.includes('client.auth.signOut()'),
  barberManagerLinksToAdminDashboard: barbers.includes('href="/admin.html"'),
  safePublicBarberView: fs.readFileSync(path.join(root, 'supabase/migrations/20261120030000_public_barber_catalog.sql'), 'utf8').includes('create or replace view public.active_barber_catalog'),
};

if (missing.length) {
  console.error('Missing required files:', missing.join(', '));
  process.exit(1);
}

for (const [name, passed] of Object.entries(checks)) {
  if (!passed) {
    console.error(`Failed check: ${name}`);
    process.exit(1);
  }
}

console.log('Site PWA foundation checks passed');
