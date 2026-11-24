const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const output = path.join(root, 'dist');
const files = [
  'index.html',
  'account.html',
  'admin.html',
  'booking.html',
  'barbers.html',
  'pos.html',
  'customers.html',
  'inventory.html',
  'transactions.html',
  'finance.html',
  'promotions.html',
  'manifest.webmanifest',
  'sw.js',
  'customer-nav.js',
  'admin-tools.js',
  'icon-192.png',
  'icon-512.png',
  'og.jpg',
  'robots.txt',
  'sitemap.xml',
  'google311d86d8ab8d8675.html'
];
const missing = files.filter((file) => !fs.existsSync(path.join(root, file)));

if (missing.length) {
  console.error('Missing website build files:', missing.join(', '));
  process.exit(1);
}

const supabaseUrl = process.env.SUPABASE_URL;
const supabasePublishableKey = process.env.SUPABASE_ANON_KEY;
const hasSupabaseEnvironment = Boolean(supabaseUrl || supabasePublishableKey);

if (hasSupabaseEnvironment && (!supabaseUrl || !supabasePublishableKey)) {
  console.error('Set both SUPABASE_URL and SUPABASE_ANON_KEY, or neither when building locally.');
  process.exit(1);
}

if (process.env.VERCEL === '1' && !hasSupabaseEnvironment) {
  console.error('Vercel production builds require SUPABASE_URL and SUPABASE_ANON_KEY environment variables.');
  process.exit(1);
}

if (hasSupabaseEnvironment) {
  let parsedUrl;
  try {
    parsedUrl = new URL(supabaseUrl);
  } catch {
    console.error('SUPABASE_URL must be a valid HTTPS URL.');
    process.exit(1);
  }
  if (parsedUrl.protocol !== 'https:' || !supabasePublishableKey.trim()) {
    console.error('SUPABASE_URL must use HTTPS and SUPABASE_ANON_KEY must not be empty.');
    process.exit(1);
  }
}

fs.rmSync(output, {recursive: true, force: true});
fs.mkdirSync(output, {recursive: true});

for (const file of files) {
  fs.copyFileSync(path.join(root, file), path.join(output, file));
}

if (hasSupabaseEnvironment) {
  const config = `window.GEMBUL_SUPABASE = Object.freeze({\n  url: ${JSON.stringify(supabaseUrl)},\n  publishableKey: ${JSON.stringify(supabasePublishableKey.trim())}\n});\n`;
  fs.writeFileSync(path.join(output, 'supabase-config.js'), config);
} else {
  fs.copyFileSync(path.join(root, 'supabase-config.js'), path.join(output, 'supabase-config.js'));
}

const images = path.join(root, 'images');
if (fs.existsSync(images)) {
  fs.cpSync(images, path.join(output, 'images'), {recursive: true});
}

console.log(`Website build prepared in ${path.relative(root, output)}`);
