#!/usr/bin/env node
import { readFileSync } from 'node:fs';

const pkg = JSON.parse(readFileSync(new URL('../package.json', import.meta.url)));
const UA = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36';

const CF = {
  cn: ['www.cloudflare-cn.com', 'www.qualcomm.cn'],
  social: [['gateway.discord.gg', 'discord'], 'x.com', 'medium.com', 'signal.org'],
  ai: ['anthropic.com', 'claude.ai', 'chatgpt.com', 'openai.com', 'sora.com', 'grok.com', 'pixpix.com', 'www.perplexity.ai', 'midjourney.com', 'mistral.ai'],
  crypto: ['coinbase.com', 'www.okx.com', ['www.binance.info', 'binance'], 'crypto.com'],
  tools: ['zoom.us', '1password.com', 'wise.com', 'poe.com', 'notion.so', 'shopify.com', 'godaddy.com', 'producthunt.com'],
  dev: ['www.cloudflare.com', 'cdnjs.cloudflare.com', 'registry.npmjs.org', 'kali.download', 'unpkg.com', 'nodejs.org', 'gitlab.com'],
  media: ['crunchyroll.com'],
};
const GROUPS = Object.keys(CF);

const HELP = `ipcheck v${pkg.version} - detect per-site exit IP (split routing), like ip.net.coffee

Usage: ipcheck [options]

Options:
  --group <a[,b]>   only check groups: ${GROUPS.join(', ')}
  --timeout <ms>    per-request timeout (default 5000)
  --no-geo          skip geo lookup of exit IPs
  --json            output JSON
  -h, --help        show help
  -v, --version     show version`;

function parseArgs(argv) {
  const o = { timeout: 5000, geo: true, json: false, groups: GROUPS };
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    const val = () => { const [k, v] = a.split('='); return v ?? argv[++i]; };
    if (a === '-h' || a === '--help') o.help = true;
    else if (a === '-v' || a === '--version') o.version = true;
    else if (a === '--json') o.json = true;
    else if (a === '--no-geo') o.geo = false;
    else if (a.startsWith('--timeout')) o.timeout = Number(val());
    else if (a.startsWith('--group')) o.groups = String(val()).split(',').map(s => s.trim()).filter(Boolean);
    else { console.error(`Unknown option: ${a}\n\n${HELP}`); process.exit(2); }
  }
  const bad = o.groups.filter(g => !GROUPS.includes(g));
  if (bad.length) { console.error(`Unknown group: ${bad.join(', ')} (valid: ${GROUPS.join(', ')})`); process.exit(2); }
  if (!(o.timeout > 0)) { console.error('Invalid --timeout'); process.exit(2); }
  return o;
}

async function timed(url, init, timeout) {
  const t0 = performance.now();
  const res = await fetch(url, { ...init, headers: { 'user-agent': UA }, signal: AbortSignal.timeout(timeout) });
  return { res, ms: Math.round(performance.now() - t0) };
}

function errMsg(e) {
  if (e?.name === 'TimeoutError' || e?.name === 'AbortError') return 'timeout';
  const c = e?.cause?.code || e?.cause?.message || e?.message || String(e);
  return String(c).slice(0, 40);
}

async function cftrace(group, entry, timeout) {
  const [domain, label] = Array.isArray(entry) ? entry : [entry, entry];
  const r = { group, site: label, method: 'cftrace', url: `https://${domain}/cdn-cgi/trace` };
  try {
    const { res, ms } = await timed(r.url, {}, timeout);
    const text = await res.text();
    r.latency = ms;
    const kv = Object.fromEntries(text.split('\n').map(l => l.split('=')).filter(p => p.length >= 2).map(([k, ...v]) => [k.trim(), v.join('=').trim()]));
    if (kv.ip) { r.ip = kv.ip; r.loc = kv.loc || ''; r.colo = kv.colo || ''; r.ok = true; }
    else { r.ok = false; r.error = `HTTP ${res.status}, no ip`; }
  } catch (e) { r.ok = false; r.error = errMsg(e); }
  return r;
}

const IP_RE = /(\d{1,3}(?:\.\d{1,3}){3}|[0-9a-fA-F]*:[0-9a-fA-F:]{2,})/;
async function header(site, url, pick, timeout) {
  const r = { group: 'cn', site, method: 'header', url };
  try {
    const { res, ms } = await timed(url, { method: 'HEAD' }, timeout);
    r.latency = ms;
    const ip = pick(res.headers);
    if (ip) { r.ip = ip; r.loc = ''; r.ok = true; } else { r.ok = false; r.error = `HTTP ${res.status}, no ip header`; }
  } catch (e) { r.ok = false; r.error = errMsg(e); }
  return r;
}

const HEADER_TESTS = [
  ['网易', 'https://necaptcha.nosdn.127.net/ab7f4275c1744aa28e0a8f3a1c58c532.png', h => h.get('cdn-user-ip')?.trim()],
  ['字节跳动', 'https://perfops.byte-test.com/500b-bench.jpg', h => h.get('x-request-ip')?.trim() || (h.get('x-response-cinfo') || '').match(IP_RE)?.[1]],
];

async function geo(ip, timeout) {
  try {
    const { res } = await timed(`https://api.ip.sb/geoip/${ip}`, {}, timeout);
    if (res.ok) { const j = await res.json(); return { country: j.country || j.country_code || '', isp: j.isp || j.organization || '', asn: j.asn ? `AS${j.asn}` : '' }; }
  } catch {}
  try {
    const { res } = await timed(`https://ipwho.is/${ip}`, {}, timeout);
    const j = await res.json();
    if (j.success !== false) return { country: j.country || '', isp: j.connection?.isp || j.connection?.org || '', asn: j.connection?.asn ? `AS${j.connection.asn}` : '' };
  } catch {}
  return null;
}

// ---- output ----
const useColor = process.stdout.isTTY && !('NO_COLOR' in process.env) || process.env.FORCE_COLOR === '1';
const sgr = n => s => useColor ? `\x1b[${n}m${s}\x1b[0m` : String(s);
const c = { bold: sgr(1), dim: sgr(2), red: sgr(31), green: sgr(32), yellow: sgr(33), blue: sgr(34), magenta: sgr(35), cyan: sgr(36) };
const PALETTE = [sgr(92), sgr(96), sgr(95), sgr(93), sgr(94), sgr(91), sgr(32), sgr(36)];

const strip = s => String(s).replace(/\x1b\[[0-9;]*m/g, '');
const width = s => [...strip(s)].reduce((w, ch) => w + (/[\u1100-\u115f\u2e80-\ua4cf\uac00-\ud7a3\uf900-\ufaff\ufe30-\ufe4f\uff00-\uff60\uffe0-\uffe6]/.test(ch) ? 2 : 1), 0);
const pad = (s, n) => s + ' '.repeat(Math.max(0, n - width(s)));

function latColor(ms) { return ms < 300 ? c.green : ms < 1000 ? c.yellow : c.red; }

function render(results, geoMap, opts) {
  const ips = [...new Set(results.filter(r => r.ok).map(r => r.ip))];
  const ipColor = ip => PALETTE[ips.indexOf(ip) % PALETTE.length](ip);
  const head = ['SITE', 'IP', 'LOC', 'LATENCY', 'STATUS'];
  const rows = results.map(r => [
    r.site,
    r.ok ? ipColor(r.ip) : c.dim('-'),
    r.loc || (r.ok && geoMap[r.ip]?.country ? c.dim(geoMap[r.ip].country) : c.dim('-')),
    r.latency != null ? latColor(r.latency)(`${r.latency}ms`) : c.dim('-'),
    r.ok ? c.green('✓ ok') : c.red(`✗ ${r.error}`),
  ]);
  const w = head.map((h, i) => Math.max(width(h), ...rows.map(row => width(row[i]))));
  const line = cells => '  ' + cells.map((x, i) => i === cells.length - 1 ? x : pad(x, w[i])).join('  ');
  const out = [];
  out.push(c.bold(`ipcheck v${pkg.version}`) + c.dim(`  — per-site exit IP check (timeout ${opts.timeout}ms)`));
  for (const g of opts.groups) {
    const idx = results.map((r, i) => r.group === g ? i : -1).filter(i => i >= 0);
    if (!idx.length) continue;
    out.push('', c.bold(c.cyan(`▸ ${g}`)));
    out.push(c.dim(line(head)));
    for (const i of idx) out.push(line(rows[i]));
  }
  return out.join('\n');
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));
  if (opts.help) return console.log(HELP);
  if (opts.version) return console.log(pkg.version);
  const tasks = [];
  for (const g of opts.groups) {
    for (const e of CF[g]) tasks.push(cftrace(g, e, opts.timeout));
    if (g === 'cn') for (const [s, u, p] of HEADER_TESTS) tasks.push(header(s, u, p, opts.timeout));
  }
  const results = await Promise.all(tasks);
  const ips = [...new Set(results.filter(r => r.ok).map(r => r.ip))];
  const geoMap = {};
  if (opts.geo) await Promise.all(ips.map(async ip => { geoMap[ip] = await geo(ip, opts.timeout); }));
  if (opts.json) {
    const exits = ips.map(ip => ({ ip, geo: geoMap[ip] ?? null, sites: results.filter(r => r.ip === ip).map(r => r.site) }));
    return console.log(JSON.stringify({ version: pkg.version, timeout: opts.timeout, results, exits }, null, 2));
  }
  console.log(render(results, geoMap, opts));
}

main().catch(e => { console.error(e); process.exit(1); });
