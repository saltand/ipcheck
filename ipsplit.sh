#!/usr/bin/env bash
# ipsplit.sh - per-site exit IP (split routing) checker, like https://ip.net.coffee/
# Needs only bash (3.2+) and curl. Usage: curl -fsSL https://<host>/sh | bash -s -- [options]
# MIT License (c) 2026 saltand
VERSION=0.1.0
UA='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Safari/537.36'
ALL_GROUPS="cn social ai crypto tools dev media"

# group|label|target|method
SITES='cn|www.cloudflare-cn.com|www.cloudflare-cn.com|cf
cn|www.qualcomm.cn|www.qualcomm.cn|cf
cn|网易|https://necaptcha.nosdn.127.net/ab7f4275c1744aa28e0a8f3a1c58c532.png|netease
cn|字节跳动|https://perfops.byte-test.com/500b-bench.jpg|bytedance
social|discord|gateway.discord.gg|cf
social|x.com|x.com|cf
social|medium.com|medium.com|cf
social|signal.org|signal.org|cf
ai|anthropic.com|anthropic.com|cf
ai|claude.ai|claude.ai|cf
ai|chatgpt.com|chatgpt.com|cf
ai|openai.com|openai.com|cf
ai|sora.com|sora.com|cf
ai|grok.com|grok.com|cf
ai|pixpix.com|pixpix.com|cf
ai|www.perplexity.ai|www.perplexity.ai|cf
ai|midjourney.com|midjourney.com|cf
ai|mistral.ai|mistral.ai|cf
crypto|coinbase.com|coinbase.com|cf
crypto|www.okx.com|www.okx.com|cf
crypto|binance|www.binance.info|cf
crypto|crypto.com|crypto.com|cf
tools|zoom.us|zoom.us|cf
tools|1password.com|1password.com|cf
tools|wise.com|wise.com|cf
tools|poe.com|poe.com|cf
tools|notion.so|notion.so|cf
tools|shopify.com|shopify.com|cf
tools|godaddy.com|godaddy.com|cf
tools|producthunt.com|producthunt.com|cf
dev|www.cloudflare.com|www.cloudflare.com|cf
dev|cdnjs.cloudflare.com|cdnjs.cloudflare.com|cf
dev|registry.npmjs.org|registry.npmjs.org|cf
dev|kali.download|kali.download|cf
dev|unpkg.com|unpkg.com|cf
dev|nodejs.org|nodejs.org|cf
dev|gitlab.com|gitlab.com|cf
media|crunchyroll.com|crunchyroll.com|cf'

usage() {
  cat <<USAGE
ipsplit.sh v$VERSION - detect per-site exit IP (split routing), like ip.net.coffee

Usage: curl -fsSL https://ip.saltand.xyz/sh | bash -s -- [options]
       bash ipsplit.sh [options]
       npx @saltand/ipcheck

Options:
  --group <a[,b]>   only check groups: ${ALL_GROUPS// /, }
  --timeout <sec>   per-request timeout in seconds (default 5)
  --no-geo          skip geo lookup of exit IPs
  --json            output JSON
  -h, --help        show help
  -v, --version     show version
USAGE
}

GROUPS_SEL=$ALL_GROUPS; TIMEOUT=5; GEO=1; JSON=0
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    -v|--version) echo "$VERSION"; exit 0 ;;
    --json) JSON=1 ;;
    --no-geo) GEO=0 ;;
    --group|--groups) shift; GROUPS_SEL=$(printf '%s' "$1" | tr ',' ' ') ;;
    --group=*|--groups=*) GROUPS_SEL=$(printf '%s' "${1#*=}" | tr ',' ' ') ;;
    --timeout) shift; TIMEOUT=$1 ;;
    --timeout=*) TIMEOUT=${1#*=} ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
for g in $GROUPS_SEL; do
  case " $ALL_GROUPS " in *" $g "*) ;; *) echo "Unknown group: $g (valid: ${ALL_GROUPS// /, })" >&2; exit 2 ;; esac
done
case "$TIMEOUT" in ''|*[!0-9.]*) echo "Invalid --timeout: $TIMEOUT" >&2; exit 2 ;; esac
command -v curl >/dev/null 2>&1 || { echo "curl is required" >&2; exit 1; }

# ---- colors ----
if [ -t 1 ] && [ -z "${NO_COLOR+x}" ] || [ "${FORCE_COLOR:-}" = 1 ]; then
  E=$(printf '\033'); R="${E}[0m"; B="${E}[1m"; D="${E}[2m"
  RED="${E}[31m"; GRN="${E}[32m"; YEL="${E}[33m"; CYN="${E}[36m"
  PAL="92 96 95 93 94 91 32 36"
else
  E=; R=; B=; D=; RED=; GRN=; YEL=; CYN=; PAL=
fi
c() { [ -n "$E" ] && printf '%s%s%s' "$1" "$2" "$R" || printf '%s' "$2"; }

# display width: ASCII = 1, multibyte CJK (3 bytes UTF-8) = 2
dwidth() {
  local LC_ALL=C s=$1 t
  t=${s//[! -~]/}
  echo $(( ${#t} + (${#s} - ${#t}) * 2 / 3 ))
}
pad() { local w; w=$(dwidth "$1"); printf '%s%*s' "$1" $(( $2 > w ? $2 - w : 0 )) ''; }

TMP=$(mktemp -d 2>/dev/null || mktemp -d -t ipsplit)
trap 'rm -rf "$TMP"' EXIT INT TERM

errname() {
  case "$1" in
    28) echo timeout ;; 6) echo "dns error" ;; 7) echo "connect failed" ;;
    35) echo "tls error" ;; 52) echo "empty reply" ;; 56) echo "recv error" ;;
    60) echo "cert error" ;; *) echo "curl error $1" ;;
  esac
}
to_ms() { awk -v t="$1" 'BEGIN{printf "%d", t*1000+0.5}'; }

# writes: ok|ip|loc|ms  or  err|message|ms
check() {
  local out="$1" method="$2" target="$3" body rc t ms ip loc code
  if [ "$method" = cf ]; then
    body=$(curl -sS -m "$TIMEOUT" -A "$UA" -w '\n__T=%{time_total}\n__C=%{http_code}\n' "https://$target/cdn-cgi/trace" 2>/dev/null); rc=$?
  else
    body=$(curl -sSI -m "$TIMEOUT" -A "$UA" -w '\n__T=%{time_total}\n__C=%{http_code}\n' "$target" 2>/dev/null); rc=$?
  fi
  if [ $rc -ne 0 ]; then echo "err|$(errname $rc)|" >"$out"; return; fi
  body=$(printf '%s\n' "$body" | tr -d '\r')
  t=$(printf '%s\n' "$body" | sed -n 's/^__T=//p'); ms=$(to_ms "$t")
  code=$(printf '%s\n' "$body" | sed -n 's/^__C=//p')
  case "$method" in
    cf) ip=$(printf '%s\n' "$body" | sed -n 's/^ip=//p' | head -n1)
        loc=$(printf '%s\n' "$body" | sed -n 's/^loc=//p' | head -n1) ;;
    netease) ip=$(printf '%s\n' "$body" | grep -i '^cdn-user-ip:' | head -n1 | sed 's/^[^:]*:[[:space:]]*//') ;;
    bytedance)
      ip=$(printf '%s\n' "$body" | grep -i '^x-request-ip:' | head -n1 | sed 's/^[^:]*:[[:space:]]*//')
      [ -z "$ip" ] && ip=$(printf '%s\n' "$body" | grep -i '^x-response-cinfo:' | head -n1 | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-fA-F]*:[0-9a-fA-F:]{2,}' | head -n1) ;;
  esac
  ip=$(printf '%s' "$ip" | tr -d ' ')
  if [ -n "$ip" ]; then echo "ok|$ip|$loc|$ms" >"$out"
  else echo "err|HTTP $code, no ip|$ms" >"$out"; fi
}

# ---- run all checks concurrently ----
SEL=$(printf '%s\n' "$SITES" | while IFS='|' read -r g l t m; do
  case " $GROUPS_SEL " in *" $g "*) echo "$g|$l|$t|$m" ;; esac
done)
i=0
while IFS='|' read -r g l t m; do
  [ -z "$g" ] && continue
  i=$((i + 1)); check "$TMP/r$i" "$m" "$t" &
done <<SEL_EOF
$SEL
SEL_EOF
wait

# rows file: group|label|status|ip_or_err|loc|ms
i=0
while IFS='|' read -r g l t m; do
  [ -z "$g" ] && continue
  i=$((i + 1)); echo "$g|$l|$(cat "$TMP/r$i" 2>/dev/null || echo 'err|no result|')"
done >"$TMP/rows" <<SEL_EOF
$SEL
SEL_EOF
# normalize to group|label|status|ip|loc|ms|err
awk -F'|' 'BEGIN{OFS="|"} $3=="ok"{print $1,$2,"ok",$4,$5,$6,""; next} {print $1,$2,"err","","",$5,$4}' "$TMP/rows" >"$TMP/norm"
awk -F'|' '$3=="ok" && !s[$4]++ {print $4}' "$TMP/norm" >"$TMP/ips"

# ---- geo ----
jget() { printf '%s' "$1" | sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\{0,1\}\([^\",}]*\).*/\1/p" | head -n1; }
geo_one() {
  local ip="$1" out="$2" j cc isp asn
  j=$(curl -sS -m "$TIMEOUT" -A "$UA" "https://api.ip.sb/geoip/$ip" 2>/dev/null)
  cc=$(jget "$j" country); isp=$(jget "$j" isp); asn=$(jget "$j" asn)
  if [ -z "$cc" ]; then
    j=$(curl -sS -m "$TIMEOUT" -A "$UA" "https://ipwho.is/$ip" 2>/dev/null)
    cc=$(jget "$j" country); isp=$(jget "$j" isp); asn=$(jget "$j" asn)
  fi
  [ -n "$asn" ] && asn="AS$asn"
  echo "$cc|$isp|$asn" >"$out"
}
n=0
if [ $GEO = 1 ]; then
  while read -r ip; do [ -n "$ip" ] && { n=$((n + 1)); geo_one "$ip" "$TMP/g$n" & }; done <"$TMP/ips"
  wait
fi
geo_of() { # $1 = ip -> "country|isp|asn"
  local k=0 x
  while read -r x; do k=$((k + 1)); [ "$x" = "$1" ] && { cat "$TMP/g$k" 2>/dev/null; return; }; done <"$TMP/ips"
}
ip_color() {
  local k=0 x np; set -- "$1" $PAL; local ip=$1; shift; np=$#
  [ $np -eq 0 ] && { printf '%s' "$ip"; return; }
  while read -r x; do [ "$x" = "$ip" ] && break; k=$((k + 1)); done <"$TMP/ips"
  shift $(( k % np )); printf '%s[%sm%s%s' "$E" "$1" "$ip" "$R"
}

TOTAL=$(wc -l <"$TMP/norm" | tr -d ' ')
OKN=$(awk -F'|' '$3=="ok"' "$TMP/norm" | wc -l | tr -d ' ')
NIPS=$(wc -l <"$TMP/ips" | tr -d ' ')

# ---- JSON ----
if [ $JSON = 1 ]; then
  esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
  printf '{\n  "version": "%s",\n  "timeout": %s,\n  "results": [\n' "$VERSION" "$TIMEOUT"
  k=0
  while IFS='|' read -r g l s ip loc ms err; do
    k=$((k + 1)); [ $k -gt 1 ] && printf ',\n'
    printf '    {"group": "%s", "site": "%s", "ok": %s' "$g" "$(esc "$l")" "$([ "$s" = ok ] && echo true || echo false)"
    [ -n "$ip" ] && printf ', "ip": "%s", "loc": "%s"' "$ip" "$loc"
    [ -n "$ms" ] && printf ', "latency": %s' "$ms"
    [ -n "$err" ] && printf ', "error": "%s"' "$(esc "$err")"
    printf '}'
  done <"$TMP/norm"
  printf '\n  ],\n  "exits": [\n'
  k=0
  while read -r ip; do
    k=$((k + 1)); [ $k -gt 1 ] && printf ',\n'
    IFS='|' read -r cc isp asn <<GEOEOF
$(geo_of "$ip")
GEOEOF
    sites=$(awk -F'|' -v ip="$ip" '$4==ip{printf "%s\"%s\"", (n++?", ":""), $2}' "$TMP/norm")
    printf '    {"ip": "%s", "country": "%s", "isp": "%s", "asn": "%s", "sites": [%s]}' "$ip" "$(esc "$cc")" "$(esc "$isp")" "$asn" "$sites"
  done <"$TMP/ips"
  printf '\n  ]\n}\n'
  exit 0
fi

# ---- table ----
W1=4; W2=2; W3=3; W4=7
while IFS='|' read -r g l s ip loc ms err; do
  [ -z "$loc" ] && [ "$s" = ok ] && [ $GEO = 1 ] && loc=$(geo_of "$ip" | cut -d'|' -f1)
  w=$(dwidth "$l"); [ "$w" -gt $W1 ] && W1=$w
  [ ${#ip} -gt $W2 ] && W2=${#ip}
  [ ${#loc} -gt $W3 ] && W3=${#loc}
  echo "$g|$l|$s|$ip|$loc|$ms|$err"
done <"$TMP/norm" >"$TMP/disp"

echo "$(c "$B" "ipsplit.sh v$VERSION")$(c "$D" "  — per-site exit IP check (timeout ${TIMEOUT}s)")"
for grp in $GROUPS_SEL; do
  grep -q "^$grp|" "$TMP/disp" || continue
  echo; echo "$(c "$B$CYN" "▸ $grp")"
  echo "$(c "$D" "  $(pad SITE $W1)  $(pad IP $W2)  $(pad LOC $W3)  $(pad LATENCY $W4)  STATUS")"
  grep "^$grp|" "$TMP/disp" | while IFS='|' read -r g l s ip loc ms err; do
    if [ "$s" = ok ]; then ipc="$(ip_color "$ip")$(pad '' $(( W2 - ${#ip} )))"; else ipc="$(c "$D" -)$(pad '' $(( W2 - 1 )))"; fi
    [ -z "$loc" ] && loc=-
    if [ -n "$ms" ]; then
      if [ "$ms" -lt 300 ]; then lc=$GRN; elif [ "$ms" -lt 1000 ]; then lc=$YEL; else lc=$RED; fi
      lat="$(c "$lc" "${ms}ms")$(pad '' $(( W4 - ${#ms} - 2 )))"
    else lat="$(c "$D" -)$(pad '' $(( W4 - 1 )))"; fi
    if [ "$s" = ok ]; then st=$(c "$GRN" "✓ ok"); else st=$(c "$RED" "✗ $err"); fi
    echo "  $(pad "$l" $W1)  $ipc  $(pad "$loc" $W3)  $lat  $st"
  done
done

echo
echo "$(c "$B" "Summary: $NIPS distinct exit IP(s), $OKN/$TOTAL sites reachable")"
while read -r ip; do
  [ -z "$ip" ] && continue
  meta=""
  if [ $GEO = 1 ]; then
    IFS='|' read -r cc isp asn <<GEOEOF
$(geo_of "$ip")
GEOEOF
    for x in "$cc" "$isp" "$asn"; do [ -n "$x" ] && meta="${meta:+$meta · }$x"; done
  fi
  echo "  $(ip_color "$ip")${meta:+  $(c "$D" "$meta")}"
  cnt=$(awk -F'|' -v ip="$ip" '$4==ip' "$TMP/norm" | wc -l | tr -d ' ')
  sites=$(awk -F'|' -v ip="$ip" '$4==ip{printf "%s%s", (n++?", ":""), $2}' "$TMP/norm")
  echo "    $(c "$D" "($cnt)") $sites"
done <"$TMP/ips" 3<&-
FAILED=$(awk -F'|' '$3!="ok"{printf "%s%s", (n++?", ":""), $2}' "$TMP/norm")
[ -n "$FAILED" ] && echo "  $(c "$RED" failed) $(c "$D" "($((TOTAL - OKN)))") $FAILED"
echo
if [ "$NIPS" -gt 1 ]; then echo "$(c "$YEL" "⚠ Split routing detected: different sites see different exit IPs.")"
elif [ "$NIPS" -eq 1 ]; then echo "$(c "$GRN" "✓ All reachable sites see the same exit IP.")"; fi
