import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const code = await readFile(new URL('../src/session.js', import.meta.url), 'utf8');
const session = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);
const cache = new Map();
globalThis.sessionStorage = {
  getItem: (key) => cache.get(key) ?? null,
  setItem: (key, value) => cache.set(key, value),
  removeItem: (key) => cache.delete(key),
};
const key = 'drone-motion.session.v1';

test('session does not allow token delivery to another project', async () => {
  cache.set(key, JSON.stringify({ access_token: 'secret', refresh_token: 'refresh', expiresAt: Date.now() + 100_000 }));
  await assert.rejects(session.accessToken('https://other.supabase.co'), /only authorizes/);
  assert.equal(await session.accessToken(session.PROJECT_URL), 'secret');
});

test('missing session is rejected instead of using an anonymous token', async () => {
  cache.clear();
  await assert.rejects(session.accessToken(session.PROJECT_URL), /Sign in/);
});

test('expired access tokens refresh once for concurrent callers', async () => {
  cache.set(key, JSON.stringify({ access_token: 'expired', refresh_token: 'refresh', expiresAt: 0 }));
  const originalFetch = globalThis.fetch;
  let calls = 0;
  globalThis.fetch = async (url, request) => {
    calls++;
    assert.equal(url, `${session.PROJECT_URL}/auth/v1/token?grant_type=refresh_token`);
    assert.equal(JSON.parse(request.body).refresh_token, 'refresh');
    return { ok: true, json: async () => ({ access_token: 'fresh', refresh_token: 'rotated', expires_in: 3600 }) };
  };
  try {
    assert.deepEqual(await Promise.all([session.accessToken(session.PROJECT_URL), session.accessToken(session.PROJECT_URL)]), ['fresh', 'fresh']);
    assert.equal(calls, 1);
    assert.equal(JSON.parse(cache.get(key)).refresh_token, 'rotated');
  } finally { globalThis.fetch = originalFetch; }
});

test('failed refresh removes the session', async () => {
  cache.set(key, JSON.stringify({ access_token: 'expired', refresh_token: 'revoked', expiresAt: 0 }));
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => ({ ok: false, json: async () => ({ error_description: 'revoked' }) });
  try {
    await assert.rejects(session.accessToken(session.PROJECT_URL), /revoked/);
    assert.equal(cache.has(key), false);
  } finally { globalThis.fetch = originalFetch; }
});
