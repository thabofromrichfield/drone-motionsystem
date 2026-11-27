// Start the alert upload immediately; evidence must never delay dispatch.
export async function deliverEventWithEvidence(row, { send, capture, attach, onError }) {
  const evidence = capture
    ? Promise.resolve().then(capture).catch((error) => { onError(error); return null; })
    : Promise.resolve(null);
  const id = await send(row);
  const result = await evidence;
  if (!result) return;
  try { await attach(id, row, result); }
  catch (error) { onError(error); }
}
