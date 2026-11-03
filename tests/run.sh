#!/usr/bin/env bash
#
# Offline regression tests for the parsers in cpux.sh, nets/nets.sh and
# worker.js. No network, no Geekbench, no iperf3 needed.
#
#   bash tests/run.sh            # all tests
#   AWK=mawk bash tests/run.sh   # force a specific awk (mawk has no {m,n})
#
# Geekbench changed its page? Save the new HTML under tests/fixtures/geekbench,
# add a line to GB_CASES with the expected scores, and make it pass.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FX="$ROOT/tests/fixtures"
pass=0; fail=0

check() { # name expected actual
  if [[ "$2" == "$3" ]]; then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); printf '  FAIL  %s: expected [%s] got [%s]\n' "$1" "$2" "$3"; fi
}

# Load functions only (each script ends with `main "$@"`).
# shellcheck disable=SC1090  # sources the scripts under test by path
load() { source <(sed '$d' "$1") </dev/null; }

# Optional awk override: wrap the awk calls inside the parsers.
if [[ -n "${AWK:-}" ]]; then awk() { command "$AWK" "$@"; }; fi

echo "cpux.sh — Geekbench score parser"
(
  load "$ROOT/cpux.sh"
  GB_CASES=(
    "result_page.html|1047 3912"
    "jina_tables.md|1047 3912"
    "jina_cards.md|1047 3912"
    "jina_bold_commas.md|12345 98765"
    "cli_summary.txt|1047 3912"
    "cloudflare_challenge.html|- -"
    "label_variants.md|2345 11872"
  )
  for c in "${GB_CASES[@]}"; do
    check "${c%%|*}" "${c#*|}" "$(parse_scores_file "$FX/geekbench/${c%%|*}")"
  done
  printf '{"ok":true,"single":1047,"multi":3912}' >"${TMPDIR:-/tmp}/cpux-api.$$"
  check "api json" "1047 3912" "$(parse_scores_api "${TMPDIR:-/tmp}/cpux-api.$$")"
  rm -f "${TMPDIR:-/tmp}/cpux-api.$$"
  exit $((fail > 0))
) || fail=$((fail + 1))

echo "nets.sh — iperf3 result classifier"
(
  load "$ROOT/nets/nets.sh"
  for c in "ok.json|ok|21367.39|2676490240" "busy.json|busy||0" "refused.json|refused||0" \
           "dns.json|dns||0" "timeout.json|timeout||0" "no_ipv6.json|noaf||0"; do
    f="${c%%|*}"
    check "$f" "${c#*|}" "$(parse_iperf 1 <"$FX/iperf3/$f")"
  done
  check "unknown option" "fail||0" "$(printf 'iperf3: unrecognized option --connect-timeout\n' | parse_iperf 1)"
  check "killed by timeout" "timeout||0" "$(printf '{\n' | parse_iperf 124)"
  exit $((fail > 0))
) || fail=$((fail + 1))

echo "nets.sh — endpoint catalog parser"
(
  load "$ROOT/nets/nets.sh"
  total=$(grep -c '"id":' "$ROOT/nets/endpoints.json")
  check "global = every endpoint" "$total" "$(endpoints_tsv "$ROOT/nets/endpoints.json" global | wc -l | tr -d ' ')"
  reduced=$(awk '/"reduced_ids"/,/]/' "$ROOT/nets/endpoints.json" | grep -c '"')
  check "reduced = reduced_ids" "$((reduced - 1))" "$(endpoints_tsv "$ROOT/nets/endpoints.json" reduced | wc -l | tr -d ' ')"
  check "regions add up" "$total" "$(for r in na eu apac; do endpoints_tsv "$ROOT/nets/endpoints.json" $r; done | wc -l | tr -d ' ')"
  check "row shape" "9" "$(endpoints_tsv "$ROOT/nets/endpoints.json" global | awk -F'\t' '{print NF}' | sort -u)"
  embedded="$(mktemp)"; write_embedded_endpoints "$embedded"
  check "embedded catalog == endpoints.json" "same" "$(cmp -s "$embedded" "$ROOT/nets/endpoints.json" && echo same || echo differs)"
  rm -f "$embedded"
  min='{"endpoints":[{"id":"a","provider":"P\"q","city":"X, Y","region":"eu","host":"h","port_range":[1,3],"speed":"1G","stack":"IPv4"},{"id":"b","host":"h2","region":"eu","enabled":false}],"reduced_ids":["a"]}'
  check "minified + escapes + enabled:false" $'a\tP"q\tX, Y\teu\th\t1\t3\t1G\tIPv4' "$(endpoints_tsv <(printf '%s' "$min") eu)"
  exit $((fail > 0))
) || fail=$((fail + 1))

if command -v node >/dev/null 2>&1; then
  echo "worker.js — server-side parser (must agree with cpux.sh)"
  node --input-type=module -e '
    import fs from "node:fs";
    const { parseGeekbenchScores } = await import(process.argv[1]);
    const fx = process.argv[2];
    const cases = { "result_page.html": [1047, 3912], "jina_tables.md": [1047, 3912], "jina_cards.md": [1047, 3912],
                    "jina_bold_commas.md": [12345, 98765], "cli_summary.txt": [1047, 3912], "cloudflare_challenge.html": [null, null],
                    "label_variants.md": [2345, 11872] };
    let bad = 0;
    for (const [f, [s, m]] of Object.entries(cases)) {
      const r = parseGeekbenchScores(fs.readFileSync(`${fx}/${f}`, "utf8"));
      const good = r.single === s && r.multi === m;
      if (!good) bad++;
      console.log(`  ${good ? "ok  " : "FAIL"}  ${f}${good ? "" : ` got ${JSON.stringify(r)}`}`);
    }
    process.exit(bad ? 1 : 0);
  ' "$ROOT/worker.js" "$FX/geekbench" || fail=$((fail + 1))
fi

echo
if ((fail > 0)); then echo "FAILED"; exit 1; fi
echo "all tests passed"
