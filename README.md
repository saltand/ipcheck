# @saltand/ipcheck

Detect which exit IP each site sees (proxy / split-routing check), like [ip.net.coffee](https://ip.net.coffee/). Runs on **your** machine or in **your** browser — not on Cloudflare’s edge — so results reflect your own network.

在终端或浏览器里检测不同网站看到的出口 IP（分流检测）。本地 / 浏览器执行，结果反映你自己的网络与代理路由。

**Live:** [https://ip.saltand.xyz](https://ip.saltand.xyz)

## Quick start

```bash
# Node CLI (zero deps, Node >= 18)
npx @saltand/ipcheck
npx @saltand/ipcheck --group ai,cn
npx @saltand/ipcheck --json --no-geo

# Bash (bash + curl only; macOS bash 3.2 OK)
curl -fsSL https://ip.saltand.xyz/sh | bash
curl -fsSL https://ip.saltand.xyz/sh | bash -s -- --group ai

# Browser — open and checks run client-side
# https://ip.saltand.xyz
```

## Options (CLI / bash)

| Flag | Description |
|------|-------------|
| `--group a,b` | Groups: `cn`, `social`, `ai`, `crypto`, `tools`, `dev`, `media` |
| `--timeout` | Per-request timeout (`ms` for Node, `sec` for bash; default 5s) |
| `--no-geo` | Skip geo enrichment of distinct IPs |
| `--json` | JSON output |
| `--help` / `--version` | Help / version |

## Methods

1. **Cloudflare trace** — `GET https://<domain>/cdn-cgi/trace`, parse `ip=` / `loc=`
2. **CN headers** — 网易 `cdn-user-ip`; 字节跳动 `x-request-ip` / `x-response-cinfo`
3. **Geo** (optional) — `api.ip.sb/geoip` with fallback `ipwho.is`

## Repo layout

| Path | What |
|------|------|
| `bin/ipcheck.js` | npm package `@saltand/ipcheck` |
| `ipsplit.sh` | Bash script served at `/sh` |
| `worker/` | Cloudflare Worker for [ip.saltand.xyz](https://ip.saltand.xyz) (HTML UI + script host) |

```bash
cd worker && npm i && npx wrangler dev   # local Worker
```


## CI & npm

GitHub Actions **CI** runs on every push/PR to `main` (Node 18/22, shellcheck + bash, Worker dry-run).

To publish `@saltand/ipcheck` to npm: add repo secret `NPM_TOKEN` (npm Automation token with publish for `@saltand`), then create a GitHub Release — workflow `Publish npm` runs `npm publish --provenance --access public`. Or publish manually from the repo root after `npm login`.

## License

MIT © [saltand](https://github.com/saltand)
