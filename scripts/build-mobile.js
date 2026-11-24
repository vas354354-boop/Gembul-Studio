const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const output = path.join(root, 'mobile', 'www');
const files = [
  'index.html',
  'account.html',
  'admin.html',
  'pos.html',
  'customers.html',
  'inventory.html',
  'transactions.html',
  'finance.html',
  'promotions.html',
  'booking.html',
  'barbers.html',
  'manifest.webmanifest',
  'sw.js',
  'supabase-config.js',
  'customer-nav.js',
  'admin-tools.js',
  'icon-192.png',
  'icon-512.png',
  'og.jpg'
];
const missing = files.filter((file) => !fs.existsSync(path.join(root, file)));

if (missing.length) {
  console.error('Missing mobile application files:', missing.join(', '));
  process.exit(1);
}

fs.rmSync(output, {recursive: true, force: true});
fs.mkdirSync(output, {recursive: true});

for (const file of files) {
  fs.copyFileSync(path.join(root, file), path.join(output, file));
}

const images = path.join(root, 'images');
if (fs.existsSync(images)) {
  fs.cpSync(images, path.join(output, 'images'), {recursive: true});
}

console.log(`Mobile web assets prepared in ${path.relative(root, output)}`);
