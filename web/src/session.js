/* Sign in to the single, explicitly configured Supabase project. No password is
 * persisted; short-lived tokens stay in this tab's sessionStorage. */
export const PROJECT_URL = 'https://ujssojzmydxcnfummtwu.supabase.co';
export const PROJECT_KEY = 'sb_publishable__qNms45omAau_DJRZyVBZQ_DdHABOmk';
const STORAGE_KEY = 'drone-motion.session.v1';

function readSession() {
  try { return JSON.parse(sessionStorage.getItem(STORAGE_KEY) || 'null'); }
  catch { return null; }
}
function saveSession(session) {
  const expiresAt = Date.now() + Math.max(0, Number(session.expires_in) || 0) * 1000;
  const saved = { access_token: session.access_token, refresh_token: session.refresh_token, expiresAt };
  sessionStorage.setItem(STORAGE_KEY, JSON.stringify(saved));
  return saved;
}
async function authRequest(grant, body) {
  const response = await fetch(`${PROJECT_URL}/auth/v1/token?grant_type=${grant}`, {
    method: 'POST',
    headers: { apikey: PROJECT_KEY, 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  const result = await response.json();
  if (!response.ok || !result.access_token || !result.refresh_token) {
    throw new Error(result.error_description || result.msg || 'Sign-in failed.');
  }
  return saveSession(result);
}

let refreshing;
export async function accessToken(url) {
  if (url !== PROJECT_URL) throw new Error('This session only authorizes the drone-motionsystem project.');
  const session = readSession();
  if (!session?.access_token) throw new Error('Sign in to access the tracking system.');
  if (session.expiresAt > Date.now() + 60_000) return session.access_token;
  if (!refreshing) {
    refreshing = authRequest('refresh_token', { refresh_token: session.refresh_token })
      .catch((error) => { sessionStorage.removeItem(STORAGE_KEY); throw error; })
      .finally(() => { refreshing = null; });
  }
  return (await refreshing).access_token;
}

async function requireOperator() {
  const token = await accessToken(PROJECT_URL);
  const response = await fetch(`${PROJECT_URL}/rest/v1/rpc/drone_is_operator`, {
    method: 'POST',
    headers: { apikey: PROJECT_KEY, authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: '{}',
  });
  if (!response.ok || await response.json() !== true) {
    sessionStorage.removeItem(STORAGE_KEY);
    throw new Error('This account is not an authorized operator.');
  }
}

export async function requireSession() {
  if (readSession()) {
    try { await requireOperator(); return; }
    catch { /* Ask for credentials again after expiry or revocation. */ }
  }
  const overlay = document.createElement('div');
  overlay.style.cssText = 'position:fixed;inset:0;z-index:99999;display:grid;place-items:center;background:#071019;color:#eef8ff;font:16px system-ui;padding:20px';
  overlay.innerHTML = `<form style="width:min(100%,380px);display:grid;gap:14px;padding:28px;border:1px solid #31505a;border-radius:12px;background:#101e28">
    <h1 style="margin:0;font-size:23px">Drone Motion System</h1>
    <p style="margin:0;line-height:1.5">Sign in with an invited operator account. New operators must verify their email.</p>
    <label>Email<input name="email" type="email" autocomplete="username" required style="display:block;width:100%;box-sizing:border-box;padding:10px;margin-top:5px"></label>
    <label>Password<input name="password" type="password" autocomplete="current-password" required style="display:block;width:100%;box-sizing:border-box;padding:10px;margin-top:5px"></label>
    <p role="alert" style="margin:0;color:#ffb5a5"></p>
    <button type="submit" style="padding:12px;cursor:pointer">Sign in</button>
    <button type="button" data-signup style="padding:12px;cursor:pointer">Create invited account</button>
  </form>`;
  document.body.appendChild(overlay);
  const form = overlay.querySelector('form');
  const error = overlay.querySelector('[role=alert]');
  return new Promise((resolve) => {
    const signup = form.querySelector('[data-signup]');
    signup.addEventListener('click', async () => {
      const email = form.elements.namedItem('email').value.trim();
      const password = form.elements.namedItem('password').value;
      if (!email || password.length < 12) {
        error.textContent = 'Enter your invited email and a password of at least 12 characters.';
        return;
      }
      signup.disabled = true;
      error.textContent = '';
      try {
        const redirect = encodeURIComponent(`${location.origin}/`);
        const response = await fetch(`${PROJECT_URL}/auth/v1/signup?redirect_to=${redirect}`, {
          method: 'POST',
          headers: { apikey: PROJECT_KEY, 'content-type': 'application/json' },
          body: JSON.stringify({ email, password }),
        });
        const result = await response.json();
        if (!response.ok) throw new Error(result.msg || result.error_description || 'Account creation failed.');
        form.elements.namedItem('password').value = '';
        error.textContent = 'Check your email for the verification link, then return here and sign in.';
      } catch (err) { error.textContent = err.message; }
      finally { signup.disabled = false; }
    });
    form.addEventListener('submit', async (event) => {
      event.preventDefault();
      const button = form.querySelector('button');
      button.disabled = true;
      error.textContent = '';
      try {
        await authRequest('password', { email: form.elements.namedItem('email').value.trim(), password: form.elements.namedItem('password').value });
        form.elements.namedItem('password').value = '';
        await requireOperator();
        overlay.remove();
        resolve();
      } catch (err) { error.textContent = err.message; }
      finally { button.disabled = false; }
    });
  });
}
