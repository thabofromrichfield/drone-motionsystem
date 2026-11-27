import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
const code = await readFile(new URL('../src/delivery.js', import.meta.url), 'utf8');
const { deliverEventWithEvidence } = await import(`data:text/javascript;base64,${Buffer.from(code).toString('base64')}`);

test('mobile alert is sent without waiting for evidence and later attaches its private path', async () => {
  let finishCapture;
  const captured = new Promise((resolve) => { finishCapture = resolve; });
  const row = { event_type: 'motion', meta: { detected_at: '2026-01-01T12:00:00Z' } };
  const calls = [];
  const delivery = deliverEventWithEvidence(row, {
    send: async (event) => { calls.push(['send', event]); return 123; },
    capture: () => captured,
    attach: async (id, event, evidence) => calls.push(['attach', id, event, evidence]),
    onError: (error) => { throw error; },
  });
  await new Promise((resolve) => setImmediate(resolve));
  assert.equal(calls.length, 1);
  assert.equal(calls[0][0], 'send');
  finishCapture({ url: 'xbox/camera/session/frame.jpg' });
  await delivery;
  assert.equal(calls[1][0], 'attach');
  assert.equal(calls[1][1], 123);
});

test('failed evidence does not suppress the alert', async () => {
  let sent = false, warned = false;
  await deliverEventWithEvidence({}, {
    send: async () => { sent = true; return 1; },
    capture: async () => { throw new Error('camera unavailable'); },
    attach: async () => { throw new Error('unexpected'); },
    onError: () => { warned = true; },
  });
  assert.ok(sent);
  assert.ok(warned);
});

test('queued event can receive evidence without an assigned ID', async () => {
  const row = {};
  await deliverEventWithEvidence(row, {
    send: async () => null,
    capture: async () => ({ url: 'xbox/frame.jpg' }),
    attach: async (id, event, evidence) => { assert.equal(id, null); event.snapshot_url = evidence.url; },
    onError: (error) => { throw error; },
  });
  assert.equal(row.snapshot_url, 'xbox/frame.jpg');
});
