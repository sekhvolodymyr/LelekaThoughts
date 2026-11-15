/** Bounded live API test. Credentials must be in an ignored, local JSON file.
 * No service key is used by simulated users. Provision/teardown is separate.
 */
import fs from 'node:fs';
import path from 'node:path';
import { performance } from 'node:perf_hooks';

const [configPath, outputPath] = process.argv.slice(2);
if (!configPath || !outputPath) throw Error('Usage: node stress-system.mjs <private-config.json> <output-directory>');
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8').replace(/^\uFEFF/, ''));
if (!/^ltstress_[a-z0-9_]+$/.test(cfg.runId) || cfg.users.length !== 100 ||
    cfg.users.some(u => !u.email.startsWith(cfg.runId + '_') || !u.email.endsWith('@example.invalid')))
  throw Error('Only a manifest of 100 isolated test accounts is accepted');
const allowedOrigin = new URL(cfg.url).origin;
const siteOrigin = new URL(cfg.site).origin;
const out = path.resolve(outputPath);
fs.mkdirSync(out, { recursive: true });
const logPath = path.join(out, 'system-stress.log');
const eventsPath = path.join(out, 'requests.jsonl');
fs.writeFileSync(logPath, ''); fs.writeFileSync(eventsPath, '');
const started = new Date();
const measures = [], checks = [], phases = [];
const users = cfg.users.map((u, i) => ({ ...u, index: i, paths: [] }));
const reuse = process.env.STRESS_REUSE_FIXTURES === '1';
if (reuse) {
  const previous = JSON.parse(fs.readFileSync(path.join(path.dirname(configPath), 'stress-state.json'), 'utf8'));
  if (previous.runId !== cfg.runId) throw Error('Fixture state mismatch');
  for (const u of users) {
    u.paths = previous.users.find(p => p.id === u.id)?.paths || [];
    if (u.paths.some(p => !p.startsWith(u.id + '/') || p.includes('..'))) throw Error('Invalid fixture path');
  }
}
let inflight = 0, peak = 0, transferred = 0, fatal = false, stage = 'setup';
const sleep = ms => new Promise(r => setTimeout(r, ms));
const clean = s => String(s).replaceAll(cfg.password, '[REDACTED]').replace(/eyJ[A-Za-z0-9_.-]+/g, '[JWT REDACTED]').slice(0, 400);
const log = text => { const line = `${new Date().toISOString()} ${clean(text)}`; fs.appendFileSync(logPath, line + '\n'); console.log(line); };
const check = (name, condition, detail = '') => {
  checks.push({ stage, name, pass: !!condition, detail: clean(detail) });
  if (!condition) log(`FAIL ${name} ${detail}`);
};
async function request(u, name, endpoint, { method = 'GET', body, headers = {}, expect = 'success', external = false } = {}) {
  if (measures.length > 10000 || transferred > 100 * 1024 * 1024) throw Error('Request/response budget exceeded');
  const url = external ? endpoint : cfg.url + endpoint;
  if (![allowedOrigin, siteOrigin].includes(new URL(url).origin)) throw Error('Unexpected request destination');
  const t = performance.now(); inflight++; peak = Math.max(peak, inflight);
  let status = 0, data, error;
  try {
    const response = await fetch(url, {
      method, signal: AbortSignal.timeout(20000), redirect: 'error',
      headers: { apikey: cfg.publicKey, ...(u?.token ? { Authorization: `Bearer ${u.token}` } : {}),
        ...(body && !Buffer.isBuffer(body) ? { 'Content-Type': 'application/json' } : {}), ...headers },
      body: body === undefined ? undefined : Buffer.isBuffer(body) ? body : JSON.stringify(body),
    });
    status = response.status;
    const raw = await response.text(); transferred += Buffer.byteLength(raw);
    try { data = JSON.parse(raw); } catch { data = raw; }
    if (!response.ok) error = clean(data?.message || data?.error_description || data?.error || `HTTP ${status}`);
  } catch (e) { error = clean(`${e.message}${e.cause?.code ? ` (${e.cause.code}: ${e.cause.message})` : ''}`); }
  finally { inflight--; }
  const success = status >= 200 && status < 300;
  const passed = expect === 'denied' ? status >= 400 && status < 500 && status !== 429 : success;
  const record = { time: new Date().toISOString(), stage, user: u?.index ?? 'anon', name, method,
    status, ms: +(performance.now() - t).toFixed(2), expected: expect, passed, ...(error ? { error } : {}) };
  measures.push(record); fs.appendFileSync(eventsPath, JSON.stringify(record) + '\n');
  if (!passed) log(`REQUEST_FAIL ${name} user=${record.user} status=${status} ${error || 'unexpected success'}`);
  if (measures.filter(m => m.status >= 500 || m.status === 0).length > 20) fatal = true;
  return { status, data, ok: success, passed };
}
const rpc = (u, action, payload = {}, expect = 'success') => request(u, action, '/rest/v1/rpc/app_action', { method: 'POST', body: { action, payload }, expect });
const read = (u, name, table, query = '') => request(u, name, `/rest/v1/${table}?${query || 'select=*&limit=30'}`);
const saveState = () => fs.writeFileSync(path.join(path.dirname(configPath), 'stress-state.json'), JSON.stringify({ runId: cfg.runId, users: users.map(({ token, ...u }) => u) }, null, 2));
async function phase(name, participants, work) {
  if (fatal) throw Error('Circuit breaker: repeated infrastructure failures');
  stage = name; const t = performance.now(), first = measures.length;
  log(`PHASE_START ${name} virtual_users=${participants.length}`);
  const results = await Promise.allSettled(participants.map(work));
  results.forEach((r, i) => { if (r.status === 'rejected') check(`${name}:worker:${i}`, false, r.reason?.message); });
  const rows = measures.slice(first);
  phases.push({ name, virtualUsers: participants.length, requests: rows.length, failed: rows.filter(x => !x.passed).length, durationMs: +(performance.now() - t).toFixed(2) });
  saveState(); log(`PHASE_END ${name} requests=${rows.length} unexpected=${rows.filter(x => !x.passed).length}`);
}
const feedSelect = encodeURIComponent('*,author:profiles!posts_author_id_fkey(*),thread:threads(*),likes(user_id),comments(id),reposts(user_id)');
const png = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=', 'base64');
log(`RUN ${cfg.runId} target=${cfg.site} backend=${cfg.url} users=100 bounded=true`);
log('METHOD API virtual users; real Auth access tokens; public client privileges. Preconfirmed fixtures bypass email provisioning only. No browser rendering, OAuth consent, SMTP or device performance measurement.');
try {
  await phase('baseline', [users[0]], async u => {
    await request(null, 'web_home', cfg.site + '/', { external: true });
    await read(null, 'anonymous_feed_baseline', 'posts', `select=${feedSelect}&order=created_at.desc&limit=20`);
    const noAuth = await rpc(null, 'post', { body: 'must be denied' }, 'denied');
    check('anonymous publish rejected', noAuth.passed);
  });
  // Ramp real password grants to respect provider auth rate limits; never hide retries.
  stage = 'login_ramp'; log('PHASE_START login_ramp users=100 interval=2300ms (respect shared provider token bucket)');
  for (let offset = 0; offset < 100; offset++) {
    const t = performance.now();
    const u = users[offset];
    for (let attempt = 0; attempt < 3; attempt++) {
      const r = await request({ index: u.index }, 'password_login', '/auth/v1/token?grant_type=password', { method: 'POST', body: { email: u.email, password: cfg.password } });
      if (r.data?.access_token && r.data?.user?.id === u.id) u.token = r.data.access_token;
      if (u.token || r.status !== 429) break;
      log(`AUTH_BACKOFF user=${u.index} attempt=${attempt + 1} wait=10000ms`); await sleep(10000);
    }
    check(`login user ${u.index}`, !!u.token);
    if ((offset + 1) % 10 === 0) log(`LOGIN_PROGRESS authenticated=${users.filter(x => x.token).length}/100`);
    await sleep(Math.max(0, 2300 - (performance.now() - t)));
  }
  if (users.some(u => !u.token)) throw Error('Not all 100 users authenticated; full load phase not valid');
  if (!reuse) await phase('onboard_100', users, async u => {
    const r = await rpc(u, 'onboard', { username: u.email.split('@')[0], display_name: `Load Test ${u.index + 1}`, birth_date: '2002-01-01', interests: ['Дизайн', 'Фото'] });
    check(`onboard ${u.index}`, r.data?.id === u.id);
  });
  // Synchronised starts verify the actual HTTP peak rather than only configured VUs.
  await phase('publish_100', users, async u => {
    const r = await rpc(u, 'post', { body: `${cfg.runId}: creator ${u.index}`, topics: ['Дизайн'] }); u.post = r.data?.id;
    check(`published ${u.index}`, !!u.post);
  });
  if (users.some(u => !u.post)) throw Error('Missing posts: stop dependent mutation phases');
  await phase('threads_100', users, async u => {
    const r = await rpc(u, 'post', { parent_id: u.post, thread_title: `${cfg.runId} ${u.index}`, body: 'Creative process continuation' });
    u.thread = r.data?.thread_id; u.part = r.data?.id; check(`thread ${u.index}`, !!u.thread);
  });
  await phase('mixed_actions_100', users, async (u, i) => {
    const peer = users[(i + 1) % 100];
    const tasks = [
      () => rpc(u, 'like', { id: peer.post }),
      () => rpc(u, 'comment', { id: peer.post, body: `${cfg.runId}: feedback ${i}` }).then(r => { u.comment = r.data?.id; }),
      () => rpc(u, 'follow', { id: peer.id }),
      () => rpc(u, 'save', { id: peer.post }),
      () => rpc(u, 'repost', { id: peer.post }),
      () => rpc(u, 'draft', { body: `${cfg.runId}: private draft`, topics: ['Фото'] }),
    ];
    for (let round = 0; round < tasks.length; round++) await tasks[(i + round) % tasks.length]();
  });
  await phase('stories_and_storage_10', users.slice(0, 10), async u => {
    const upload = await request(u, 'upload_png', '/functions/v1/media', { method: 'POST', body: png, headers: { 'Content-Type': 'image/png' } });
    if (!upload.ok) return;
    const objectPath = upload.data.path; u.paths.push(objectPath); saveState();
    const r = await rpc(u, 'story', { media: { ...upload.data }, caption: cfg.runId, series_title: `${cfg.runId} ${u.index}`, thread_id: u.thread, post_id: u.part });
    u.story = r.data?.id; check(`story ${u.index}`, !!u.story);
    const row = await read(u, 'series_link', 'stories', `select=id,series_id&id=eq.${u.story}`); u.series = row.data?.[0]?.series_id;
  });
  await phase('story_views_100', users, async (u, i) => {
    const target = users[i % 10]; if (!target.story) return;
    await rpc(u, 'view_story', { id: target.story });
    await rpc(u, 'view_story', { id: target.story });
    await rpc(u, 'like_story', { id: target.story });
  });
  const pairs = users.filter((u, i) => i % 2 === 0);
  await phase('chat_requests_50', pairs, async u => {
    const peer = users[u.index + 1];
    const r = await rpc(u, 'send', { recipient_id: peer.id, body: `${cfg.runId}: request` }); u.conversation = r.data?.id;
    check(`chat created ${u.index}`, !!u.conversation);
    check(`one pending message ${u.index}`, (await rpc(u, 'send', { recipient_id: peer.id, body: 'second before acceptance' }, 'denied')).passed);
  });
  await phase('chat_acceptance_100', users, async u => {
    const initiator = users[u.index - 1];
    if (u.index % 2) await rpc(u, 'accept_chat', { id: initiator.conversation, accept: true });
    else await read(u, 'chat_history', 'messages', `select=*&conversation_id=eq.${u.conversation}&limit=30`);
  });
  await phase('chat_replies_100', users, async u => {
    const peer = users[u.index % 2 ? u.index - 1 : u.index + 1];
    await rpc(u, 'send', { recipient_id: peer.id, body: `${cfg.runId}: accepted reply ${u.index}` });
  });
  await phase('mixed_reads_100', users, async (u, i) => {
    const queries = [
      ['feed', 'posts', `select=${feedSelect}&order=created_at.desc&limit=20`],
      ['people_search', 'profiles', `select=*&username=ilike.${cfg.runId}*&limit=40`],
      ['notifications', 'notifications', 'select=*&order=created_at.desc&limit=100'],
      ['thread_read', 'posts', `select=${feedSelect}&thread_id=eq.${u.thread}&order=part&limit=30`],
      ['saved', 'saves', 'select=post_id&limit=100'],
    ];
    for (let round = 0; round < queries.length; round++) {
      const [name, table, query] = queries[(round + i) % queries.length]; await read(u, name, table, query);
    }
  });
  await phase('security_isolation_100', users, async (u, i) => {
    const stranger = users[(i + 4) % 100];
    for (const [table, filter] of [['drafts', `user_id=eq.${stranger.id}`], ['saves', `user_id=eq.${stranger.id}`], ['account_settings', `id=eq.${stranger.id}`], ['notifications', `recipient_id=eq.${stranger.id}`]]) {
      const r = await read(u, `private_${table}`, table, `select=*&${filter}`);
      check(`${table} isolated user ${i}`, r.ok && Array.isArray(r.data) && r.data.length === 0);
    }
    const conv = users[(Math.floor((i + 4) / 2) * 2) % 100].conversation;
    const privateMessages = await read(u, 'private_chat', 'messages', `select=*&conversation_id=eq.${conv}`);
    check(`chat isolated user ${i}`, privateMessages.ok && Array.isArray(privateMessages.data) && privateMessages.data.length === 0);
    for (const [action, payload] of [
      ['edit_post', { id: stranger.post, body: 'unauthorized edit' }],
      ['delete_post', { id: stranger.post }],
      ['post', { parent_id: stranger.post, body: 'unauthorized continuation' }],
      ['admin', { id: stranger.post, operation: 'hide_post' }],
    ]) check(`${action} denied user ${i}`, (await rpc(u, action, payload, 'denied')).passed);
  });
  await phase('boundary_security', users.slice(0, 10), async (u, i) => {
    const peer = users[(i + 30) % 100];
    check(`oversized post ${i}`, (await rpc(u, 'post', { body: 'x'.repeat(1001) }, 'denied')).passed);
    check(`foreign media path ${i}`, (await rpc(u, 'post', { body: 'test', media: [{ path: `${peer.id}/not-owned.png`, type: 'image/png', src: 'https://example.invalid/image.png' }] }, 'denied')).passed);
    const direct = await request(u, 'direct_table_write', '/rest/v1/posts', { method: 'POST', body: { author_id: peer.id, body: 'forged author' }, expect: 'denied' });
    check(`direct write denied ${i}`, direct.passed);
    if (i === 0) {
      check('proxy missing authorization', (await request(null, 'proxy_no_auth', cfg.site + '/api/account', { external: true, method: 'POST', body: { action: 'delete_account' }, expect: 'denied' })).passed);
      check('forged JWT rejected', (await request({ index: 'forged', token: 'invalid.invalid.invalid' }, 'forged_jwt', '/rest/v1/profiles?select=id&limit=1', { expect: 'denied' })).passed);
    }
  });
  await phase('block_enforcement_10', users.slice(0, 10), async (u, i) => {
    const peer = users[(i + 50) % 100];
    await rpc(u, 'block', { id: peer.id });
    const hidden = await read(u, 'blocked_feed', 'posts', `select=id&author_id=eq.${peer.id}`);
    check(`blocked content hidden ${i}`, hidden.ok && hidden.data?.length === 0);
    check(`blocked interaction ${i}`, (await rpc(peer, 'like', { id: u.post }, 'denied')).passed);
    check(`blocked messaging ${i}`, (await rpc(peer, 'send', { recipient_id: u.id, body: 'must be denied' }, 'denied')).passed);
  });
  await phase('thread_race_8', Array.from({ length: 8 }, (_, i) => i), async i => {
    await rpc(users[99], 'post', { parent_id: users[99].post, body: `Concurrent part ${i}` });
  });
  await phase('integrity', [users[99]], async u => {
    const r = await read(u, 'thread_order', 'posts', `select=id,part&thread_id=eq.${u.thread}&order=part`);
    check('thread race preserves unique sequential parts', r.data?.length === 10 && r.data.every((p, i) => p.part === i + 1));
    for (const owner of users.slice(0, 10)) {
      const view = await read(owner, 'story_unique_views', 'story_views', `select=viewer_id&story_id=eq.${owner.story}`);
      const fixtureIds = new Set(users.map(x => x.id));
      const fixtureViews = Array.isArray(view.data) ? view.data.filter(x => fixtureIds.has(x.viewer_id)) : [];
      check(`story deduplicates account views ${owner.index}`, view.ok && fixtureViews.length === 10 && new Set(fixtureViews.map(x => x.viewer_id)).size === 10);
    }
    const original = await read(users[0], 'ownership_unchanged', 'posts', `select=body&id=eq.${users[0].post}`);
    check('failed cross-account edits left content unchanged', original.data?.[0]?.body === `${cfg.runId}: creator 0`);
    await request(null, 'web_home_after_load', cfg.site + '/', { external: true });
  });
} catch (e) { fatal = true; log(`ABORT ${e.message}`); check('completed all planned phases', false, e.message); }
finally {
  stage = 'cleanup_storage_and_sessions';
  const cleanupUsers = users.slice();
  await Promise.allSettled(Array.from({length: 5}, async () => {
    while (cleanupUsers.length) {
    const u = cleanupUsers.shift();
    if (!u.token) continue;
    if (u.paths.length) await request(u, 'remove_test_media', '/storage/v1/object/media', { method: 'DELETE', body: { prefixes: u.paths } });
    await request(u, 'sign_out', '/auth/v1/logout?scope=global', { method: 'POST' });
    delete u.token;
    }
  }));
  saveState();
  const ended = new Date();
  const quantile = (a, p) => a.length ? +a.slice().sort((x, y) => x - y)[Math.ceil(p * a.length) - 1].toFixed(2) : null;
  const groups = {};
  for (const m of measures) (groups[m.name] ||= []).push(m);
  const statistics = rows => ({ requests: rows.length, unexpected: rows.filter(x => !x.passed).length,
    p50Ms: quantile(rows.map(x => x.ms), .5), p95Ms: quantile(rows.map(x => x.ms), .95), p99Ms: quantile(rows.map(x => x.ms), .99), maxMs: Math.max(...rows.map(x => x.ms)) });
  const normal = measures.filter(m => m.expected === 'success');
  const summary = { runId: cfg.runId, started: started.toISOString(), ended: ended.toISOString(),
    virtualUsers: 100, authenticatedUsers: checks.filter(c => c.name.startsWith('login user ') && c.pass).length,
    peakInflightRequests: peak, durationSeconds: (ended - started) / 1000, responseBytes: transferred,
    overall: statistics(measures), normalRequests: statistics(normal),
    httpStatuses: measures.reduce((a, m) => ({ ...a, [m.status]: (a[m.status] || 0) + 1 }), {}),
    assertions: { total: checks.length, passed: checks.filter(x => x.pass).length, failed: checks.filter(x => !x.pass) },
    phases, byOperation: Object.fromEntries(Object.entries(groups).map(([k, rows]) => [k, statistics(rows)])),
    limitations: ['API-level virtual users, not 100 rendered browsers or physical devices', 'Auth fixtures preconfirmed by operator; email delivery/OAuth/registration rate limits excluded', 'Bounded burst/mixed workload, not a sustained soak or capacity ceiling', 'No disabling rate limits or changing paid plans', 'Database teardown still requires operator-scoped fixture cleanup'], fatal };
  fs.writeFileSync(path.join(out, 'summary.json'), JSON.stringify(summary, null, 2));
  log(`RESULT users=${summary.authenticatedUsers}/100 peak_inflight=${peak} requests=${measures.length} unexpected=${summary.overall.unexpected} assertions=${summary.assertions.passed}/${checks.length} p95=${summary.normalRequests.p95Ms}ms bytes=${transferred}`);
  log('DATABASE_TEARDOWN=PENDING operator must remove only run-manifest users and their generated records.');
  process.exitCode = fatal || summary.assertions.failed.length || summary.overall.unexpected ? 1 : 0;
}
