import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const code = await readFile(new URL('../src/supabase.js', import.meta.url), 'utf8');
const { XboxApi } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);

test('private evidence is signed with the operator token and cached', async () => {
  const api = new XboxApi({ url: 'https://example.supabase.co', key: 'publishable', bucket: 'xbox-snapshots' });
  const originalFetch = globalThis.fetch;
  const oldSession = globalThis.droneSession;
  let calls = 0;
  globalThis.droneSession = { accessToken: async () => 'operator-token' };
  globalThis.fetch = async (url, options) => {
    calls++;
    assert.equal(url, 'https://example.supabase.co/storage/v1/object/sign/xbox-snapshots/xbox/camera/frame.jpg');
    assert.equal(options.headers.authorization, 'Bearer operator-token');
    return { ok: true, json: async () => ({ signedURL: '/object/sign/xbox-snapshots/xbox/camera/frame.jpg?token=short-lived' }) };
  };
  try {
    const event = { id: 1, snapshot_url: 'xbox/camera/frame.jpg' };
    const signed = await api.withSignedSnapshot(event);
    assert.equal(signed.snapshot_url, 'https://example.supabase.co/storage/v1/object/sign/xbox-snapshots/xbox/camera/frame.jpg?token=short-lived');
    assert.deepEqual(await api.withSignedSnapshot(event), signed);
    assert.equal(calls, 1);
    assert.equal(event.snapshot_url, 'xbox/camera/frame.jpg');
  } finally { globalThis.fetch = originalFetch; globalThis.droneSession = oldSession; }
});

test('external snapshot URLs are not fetched or displayed', async () => {
  const api = new XboxApi({ url: 'https://example.supabase.co', key: 'publishable' });
  const originalFetch = globalThis.fetch;
  globalThis.fetch = () => { throw new Error('unexpected network request'); };
  try { assert.equal((await api.withSignedSnapshot({ snapshot_url: 'https://attacker.invalid/file' })).snapshot_url, null); }
  finally { globalThis.fetch = originalFetch; }
});
