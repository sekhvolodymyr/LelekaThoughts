// Retry only fixture media cleanup after the load generator has stopped.
import fs from 'node:fs';
const [manifest, output] = process.argv.slice(2);
const cfg = JSON.parse(fs.readFileSync(manifest, 'utf8').replace(/^\uFEFF/, ''));
const state = JSON.parse(fs.readFileSync(new URL('../../.tooling/stress-state.json', import.meta.url), 'utf8'));
if (state.runId !== cfg.runId) throw Error('Fixture state does not match manifest');
if (!/^ltstress_[a-z0-9_]+$/.test(cfg.runId) || cfg.users.length !== 100) throw Error('Invalid fixture manifest');
const log = line => { const text = `${new Date().toISOString()} ${line}\n`; fs.appendFileSync(output, text); console.log(text.trim()); };
let failed = 0;
for (const [index, u] of cfg.users.slice(0, 10).entries()) {
  if (!u.email.startsWith(cfg.runId + '_') || !u.email.endsWith('@example.invalid')) throw Error('Unexpected account');
  try {
    const auth = await fetch(cfg.url + '/auth/v1/token?grant_type=password', {
      method: 'POST', signal: AbortSignal.timeout(15000), headers: { apikey: cfg.publicKey, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: u.email, password: cfg.password }),
    });
    const session = await auth.json();
    if (!auth.ok || session.user?.id !== u.id) throw Error(`Login HTTP ${auth.status}`);
    const result = await fetch(cfg.url + '/storage/v1/object/media', {
      method: 'DELETE', signal: AbortSignal.timeout(15000),
      headers: { apikey: cfg.publicKey, Authorization: `Bearer ${session.access_token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ prefixes: (() => {
        const paths = state.users.find(x => x.id === u.id)?.paths || [];
        if (paths.some(p => !p.startsWith(u.id + '/') || p.includes('..'))) throw Error('Invalid fixture media path');
        return paths;
      })() }),
    });
    await result.text();
    if (!result.ok) throw Error(`Storage HTTP ${result.status}`);
    log(`RECOVERY_MEDIA user=${index} status=${result.status}`);
    const logout = await fetch(cfg.url + '/auth/v1/logout?scope=global', { method: 'POST', signal: AbortSignal.timeout(15000), headers: { apikey: cfg.publicKey, Authorization: `Bearer ${session.access_token}` } });
    await logout.text(); log(`RECOVERY_LOGOUT user=${index} status=${logout.status}`);
  } catch (e) { failed++; log(`RECOVERY_ERROR user=${index} message=${e.message} cause=${e.cause?.code || 'none'}`); }
  await new Promise(r => setTimeout(r, 2300));
}
log(`RECOVERY_RESULT failures=${failed}`); process.exitCode = failed ? 1 : 0;
