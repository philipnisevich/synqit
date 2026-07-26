// Thin client for the Jac service. Two distinct failure shapes to handle:
// framework-level (`ok: false`, e.g. bad auth, 404) and our own walkers'
// soft errors (`ok: true`, but the reported value is `{"error": "..."}`) -
// callWalker surfaces both the same way so callers only check one thing.

async function request(url, options = {}) {
  let response;
  try {
    response = await fetch(url, options);
  } catch {
    throw new Error(`Could not reach Synqit at ${new URL(url).origin}.`);
  }
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body.ok === false) {
    const message = body.error?.message || body.error || `Server responded ${response.status}.`;
    throw new Error(message);
  }
  return body;
}

function headers(token) {
  const h = { 'content-type': 'application/json' };
  if (token) h.authorization = `Bearer ${token}`;
  return h;
}

export async function register(base, username, password) {
  const body = await request(`${base}/user/register`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      identities: [{ type: 'username', value: username }],
      credential: { type: 'password', password },
    }),
  });
  return body.data;
}

export async function login(base, username, password) {
  const body = await request(`${base}/user/login`, {
    method: 'POST',
    headers: headers(),
    body: JSON.stringify({
      identity: { type: 'username', value: username },
      credential: { type: 'password', password },
    }),
  });
  return body.data;
}

// Every walker in this service reports exactly one value. Unwrap to that
// value, and treat a reported `{"error": ...}` the same as a hard failure -
// callers never need to know which failure style produced it.
export async function callWalker(base, token, name, payload, { timeoutMs = 180000 } = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  let body;
  try {
    body = await request(`${base}/walker/${name}`, {
      method: 'POST',
      headers: headers(token),
      body: JSON.stringify(payload),
      signal: controller.signal,
    });
  } catch (err) {
    if (err.name === 'AbortError') throw new Error(`${name} timed out after ${Math.round(timeoutMs / 1000)}s.`);
    throw err;
  } finally {
    clearTimeout(timer);
  }
  const reports = body.data?.reports || [];
  const result = reports[0];
  if (result && typeof result === 'object' && 'error' in result) {
    throw new Error(typeof result.error === 'string' ? result.error : JSON.stringify(result.error));
  }
  return result;
}
