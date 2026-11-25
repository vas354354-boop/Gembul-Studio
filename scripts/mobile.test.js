const assert = require('node:assert/strict');
const {execFileSync} = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const mobileOutput = path.join(root, 'mobile', 'www');

test('mobile build packages customer, admin, and business operation pages', () => {
  execFileSync(process.execPath, [path.join(__dirname, 'build-mobile.js')], {cwd: root});

  for (const page of ['index.html', 'account.html', 'booking.html', 'admin.html', 'barbers.html', 'pos.html', 'customers.html', 'inventory.html', 'transactions.html', 'finance.html', 'promotions.html']) {
    assert.ok(fs.existsSync(path.join(mobileOutput, page)), `expected ${page} in the app bundle`);
  }
  assert.ok(fs.existsSync(path.join(mobileOutput, 'customer-nav.js')));
  assert.ok(fs.existsSync(path.join(mobileOutput, 'admin-tools.js')));
  assert.ok(fs.existsSync(path.join(mobileOutput, 'images', 'g01.jpg')));
});

test('mobile build excludes server configuration and database migrations', () => {
  assert.equal(fs.existsSync(path.join(mobileOutput, '.env')), false);
  assert.equal(fs.existsSync(path.join(mobileOutput, 'supabase')), false);
});

test('Android and iOS Capacitor platform projects are present', () => {
  assert.ok(fs.existsSync(path.join(root, 'android', 'app', 'build.gradle')));
  assert.ok(fs.existsSync(path.join(root, 'ios', 'App', 'App.xcodeproj', 'project.pbxproj')));
});
