import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

process.env.SUPABASE_URL = 'https://example.supabase.co';
process.env.SUPABASE_SERVICE_ROLE_KEY = 'test-service-key';
process.env.XBOX_AUTO_REGISTER = 'false';
delete process.env.XBOX_INGEST_TOKEN;
const require = createRequire(import.meta.url);
const handler = require('../api/event.js');

function response() {
  return {
    headers: {}, code: 200, body: undefined,
    setHeader(name, value) { this.headers[name] = value; },
    status(code) { this.code = code; return this; },
    json(body) { this.body = body; return this; },
    end() { return this; },
  };
}

const jsonResponse = (value) => ({ ok: true, status: 200, json: async () => value });

test('ingest denies missing token without touching database', async () => {
  const old = globalThis.fetch;
  globalThis.fetch = () => { throw new Error('unexpected database request'); };
  try {
    const res = response();
    await handler({ method: 'POST', headers: {}, body: { event_type: 'motion' } }, res);
    assert.equal(res.code, 401);
  } finally { globalThis.fetch = old; }
});

test('unknown camera token is rejected', async () => {
  const old = globalThis.fetch;
  globalThis.fetch = async () => jsonResponse([]);
  try {
    const res = response();
    await handler({ method: 'POST', headers: { 'x-xbox-token': 'unknown' }, body: { event_type: 'motion' } }, res);
    assert.equal(res.code, 401);
  } finally { globalThis.fetch = old; }
});

test('registered camera token sends detected timestamp to the event queue', async () => {
  const old = globalThis.fetch;
  const stamp = '2026-01-01T12:00:00.000Z';
  let inserted;
  globalThis.fetch = async (url, options) => {
    assert.equal(options.headers.authorization, 'Bearer test-service-key');
    if (url.includes('/xbox_cameras?')) return jsonResponse([{ id: 'camera-id', label: 'Gate', access_token: 'camera-token' }]);
    if (url.includes('/xbox_detection_events?')) {
      inserted = JSON.parse(options.body);
      return jsonResponse([{ id: 42, event_type: 'motion', severity: 'motion', is_alert: true }]);
    }
    throw new Error(`unexpected endpoint ${url}`);
  };
  try {
    const res = response();
    await handler({ method: 'POST', headers: { 'x-xbox-token': 'camera-token' }, body: {
      event_type: 'motion', session_id: 'camera-session', meta: { detected_at: stamp },
    } }, res);
    assert.equal(res.code, 201);
    assert.equal(inserted.camera_id, 'camera-id');
    assert.equal(inserted.session_id, 'camera-session');
    assert.equal(inserted.meta.detected_at, stamp);
  } finally { globalThis.fetch = old; }
});
