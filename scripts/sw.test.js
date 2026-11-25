const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const vm = require('node:vm');

const workerSource = fs.readFileSync(path.join(__dirname, '..', 'sw.js'), 'utf8');

function createWorkerHarness(options = {}) {
  const listeners = new Map();
  const cacheEntries = new Map();
  const cacheNames = options.cacheNames || ['gembul-static-v3', 'other-app-cache'];
  const cache = {
    addAll: async (urls) => urls.forEach((url) => cacheEntries.set(url, {url})),
    put: async (request, response) => cacheEntries.set(request.url || request, response),
    match: async (request) => cacheEntries.get(request.url || request) || null
  };
  let fetchCalls = 0;
  const fetchOptions = [];
  const context = {
    URL,
    Response: class Response {
      constructor(body, responseOptions) {
        this.body = body;
        this.status = responseOptions.status;
        this.headers = responseOptions.headers;
      }
    },
    self: {
      location: {origin: 'https://gembul.example'},
      clients: {claim: async () => {}},
      skipWaiting: async () => {},
      addEventListener: (name, handler) => listeners.set(name, handler)
    },
    caches: {
      open: async () => cache,
      match: cache.match,
      keys: async () => cacheNames,
      delete: async (key) => { cacheNames.splice(cacheNames.indexOf(key), 1); return true; }
    },
    fetch: async (request, requestOptions) => {
      fetchCalls++;
      fetchOptions.push(requestOptions);
      if (options.fetchFails) throw new Error('offline');
      return {ok: true, status: 200, clone() { return this; }, url: request.url};
    }
  };

  vm.runInNewContext(workerSource, context);

  return {
    cacheEntries,
    cacheNames,
    fetchOptions,
    get fetchCalls() { return fetchCalls; },
    trigger(name, event) { listeners.get(name)(event); }
  };
}

test('install precaches only public application shell and assets', async () => {
  const worker = createWorkerHarness();
  let completed;
  worker.trigger('install', {waitUntil: (promise) => { completed = promise; }});
  await completed;

  for (const asset of ['/', '/manifest.webmanifest', '/supabase-config.js', '/customer-nav.js', '/admin-tools.js?v=2', '/icon-192.png', '/icon-512.png', '/og.jpg']) {
    assert.ok(worker.cacheEntries.has(asset), `expected ${asset} in the app cache`);
  }
  for (const asset of ['/account.html', '/admin.html', '/booking.html', '/barbers.html', '/pos.html', '/customers.html', '/inventory.html', '/transactions.html', '/finance.html', '/promotions.html']) {
    assert.ok(!worker.cacheEntries.has(asset), `sensitive page ${asset} must not be cached`);
  }
});

test('activation removes only stale Gembul caches', async () => {
  const worker = createWorkerHarness();
  let completed;
  worker.trigger('activate', {waitUntil: (promise) => { completed = promise; }});
  await completed;

  assert.deepEqual(worker.cacheNames, ['other-app-cache']);
});

test('fetch leaves cross-origin and non-GET requests untouched', () => {
  const worker = createWorkerHarness();
  const external = {request: {method: 'GET', url: 'https://supabase.example/rest/v1/services', mode: 'cors'}, respondWith() { throw new Error('should not intercept external requests'); }};
  const mutation = {request: {method: 'POST', url: 'https://gembul.example/api', mode: 'cors'}, respondWith() { throw new Error('should not intercept POST requests'); }};

  worker.trigger('fetch', external);
  worker.trigger('fetch', mutation);

  assert.equal(worker.fetchCalls, 0);
});

test('offline public navigation falls back to the cached home page', async () => {
  const worker = createWorkerHarness({fetchFails: true});
  worker.cacheEntries.set('/', {url: '/'});
  let responsePromise;
  worker.trigger('fetch', {
    request: {method: 'GET', url: 'https://gembul.example/about.html', mode: 'navigate'},
    respondWith: (promise) => { responsePromise = promise; }
  });

  assert.deepEqual(await responsePromise, {url: '/'});
});

test('private pages always use network and never receive cached content offline', async () => {
  const worker = createWorkerHarness({fetchFails: true});
  worker.cacheEntries.set('/admin.html', {url: '/admin.html', private: true});
  let responsePromise;
  worker.trigger('fetch', {
    request: {method: 'GET', url: 'https://gembul.example/admin.html', mode: 'navigate'},
    respondWith: (promise) => { responsePromise = promise; }
  });

  const response = await responsePromise;
  assert.equal(response.status, 503);
  assert.equal(response.headers['Cache-Control'], 'no-store');
  assert.equal(worker.fetchOptions[0].cache, 'no-store');
  assert.equal(worker.fetchCalls, 1);
});

test('offline non-navigation requests do not receive HTML as a fake fallback', async () => {
  const worker = createWorkerHarness({fetchFails: true});
  let responsePromise;
  worker.trigger('fetch', {
    request: {method: 'GET', url: 'https://gembul.example/missing.js', mode: 'same-origin'},
    respondWith: (promise) => { responsePromise = promise; }
  });

  await assert.rejects(responsePromise, /offline/);
});
