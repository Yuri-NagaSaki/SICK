/**
 * catbash.net / 猫脚本 — short install URLs + static site
 *
 * Pages (HTML):
 *   /           → 猫脚本 hub (index.html)  [worker maps / because html_handling=none]
 *   /sick.html  → SICK intro
 *   /nets.html  → NETS intro
 *   /cpux.html  → CPUX intro
 *
 * Scripts (text/plain, curl|bash):
 *   /menu /catbash /catbash.sh → catbash.sh (launcher menu)
 *   /sick  /sick/  → hardware_info.sh
 *   /nets  /nets/  → nets/nets.sh
 *   /nets.sh       → nets/nets.sh
 *   /cpux  /cpux/  → cpux.sh
 *   /cpux.sh       → cpux.sh
 *
 * API:
 *   /api/gb?url=…  → Geekbench result scores as JSON (CPUX fallback)
 *
 * html_handling is "none" so /sick.html is NOT redirected to /sick
 * (which would collide with the install short link).
 *
 * External short links (ba.sh):
 *   https://ba.sh/sick · https://ba.sh/nets · https://ba.sh/cpux · ba.sh/menu
 */
function asScript(res) {
  const headers = new Headers(res.headers);
  headers.set("Content-Type", "text/plain; charset=utf-8");
  headers.set("Cache-Control", "public, max-age=300");
  headers.set("X-Content-Type-Options", "nosniff");
  return new Response(res.body, {
    status: res.status,
    statusText: res.statusText,
    headers,
  });
}

async function asset(env, request, path) {
  const assetReq = new Request(new URL(path, new URL(request.url).origin), request);
  return env.ASSETS.fetch(assetReq);
}

/*
 * GET /api/gb?url=https://browser.geekbench.com/v6/cpu/123456
 *   → {"ok":true,"single":1047,"multi":3912,"url":"…"}
 *
 * Score fallback for cpux.sh: the Geekbench tryout CLI never prints scores
 * and browser.geekbench.com often challenges datacenter IPs, so the page is
 * fetched here (Cloudflare network) and parsed server-side. Only Geekbench
 * CPU result URLs are accepted — this is not an open proxy.
 *
 * Status codes are part of the contract cpux.sh relies on:
 *   200 ok:true          scores found (cached for a day)
 *   200 ok:false         page not ready yet — client keeps retrying
 *   400                  bad url
 *   502                  upstream blocked/broken — client stops asking
 */
const GB_URL_RE = /^https:\/\/browser\.geekbench\.com\/v([4-9])\/cpu\/(\d{1,12})\/?$/;
const GB_UA =
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36";

// Same algorithm as parse_scores_file() in cpux.sh: tokenize, then pair each
// "Single-Core Score"/"Multi-Core Score" label with an adjacent number; a
// number before the label (score card) outranks one after it (table row).
export function parseGeekbenchScores(text) {
  const tokens = text
    .replace(/<script[\s\S]*?<\/script>/gi, "\n")
    .replace(/<style[\s\S]*?<\/style>/gi, "\n")
    .replace(/<[^>]*>/g, "\n")
    .replace(/\|/g, "\n")
    .replace(/&nbsp;/g, " ")
    .split("\n")
    .map((t) => t.replace(/[*_`#]/g, "").replace(/\s+/g, " ").trim())
    .filter((t) => t && !/^:?-+:?$/.test(t));

  const pick = (kind) => {
    const lab = `${kind}[- ]?(?:core|thread|threaded)(?: score)?`;
    const label = new RegExp(`^${lab}$`, "i");
    const numFirst = new RegExp(`^([0-9,]+) ${lab}$`, "i");
    const labelFirst = new RegExp(`^${lab} ?:? ?([0-9,]+)$`, "i");
    const votes = new Map();
    const vote = (raw, weight) => {
      const v = String(raw || "").replace(/,/g, "");
      if (/^\d{1,7}$/.test(v) && Number(v) > 0) votes.set(v, (votes.get(v) || 0) + weight);
    };
    tokens.forEach((t, i) => {
      let m;
      if (label.test(t)) {
        vote(tokens[i - 1], 1.5);
        vote(tokens[i + 1], 1);
      } else if ((m = t.match(numFirst)) || (m = t.match(labelFirst))) {
        vote(m[1], 3);
      }
    });
    let best = null;
    let bestWeight = 0;
    for (const [v, w] of votes) if (w > bestWeight) [best, bestWeight] = [Number(v), w];
    return best;
  };
  return { single: pick("single"), multi: pick("multi") };
}

function json(data, status = 200, extra = {}) {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
      ...extra,
    },
  });
}

async function geekbenchScores(request, ctx) {
  const reqUrl = new URL(request.url);
  const target = (reqUrl.searchParams.get("url") || "").replace(/\/$/, "");
  if (!GB_URL_RE.test(target)) return json({ ok: false, error: "expected a browser.geekbench.com CPU result URL" }, 400);

  const cache = caches.default;
  const cacheKey = new Request(`${reqUrl.origin}/api/gb?url=${encodeURIComponent(target)}`);
  const hit = await cache.match(cacheKey);
  if (hit) return hit;

  let upstream;
  try {
    upstream = await fetch(target, {
      headers: {
        "User-Agent": GB_UA,
        Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
      },
      redirect: "follow",
      cf: { cacheTtl: 0 },
    });
  } catch (e) {
    return json({ ok: false, error: "upstream fetch failed", url: target }, 502);
  }

  // Result pages can 404 for a short while right after upload.
  if (upstream.status === 404) return json({ ok: false, pending: true, upstream: 404, url: target });
  if (!upstream.ok) return json({ ok: false, upstream: upstream.status, url: target }, 502);

  const { single, multi } = parseGeekbenchScores(await upstream.text());
  if (!single || !multi) return json({ ok: false, pending: true, upstream: 200, url: target, single, multi });

  // Published results never change — cache hits skip the upstream entirely.
  const res = json({ ok: true, single, multi, url: target }, 200, { "Cache-Control": "public, max-age=86400" });
  ctx.waitUntil(cache.put(cacheKey, res.clone()));
  return res;
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname;

    // CPUX score fallback (see geekbenchScores)
    if (path === "/api/gb") {
      if (request.method !== "GET" && request.method !== "HEAD") return json({ ok: false }, 405);
      return geekbenchScores(request, ctx);
    }

    // Hub home — assets.html_handling=none does not auto-serve index.html for /
    if (path === "/" || path === "") {
      return asset(env, request, "/index.html");
    }

    // Launcher menu (猫脚本)
    if (
      path === "/menu" ||
      path === "/menu/" ||
      path === "/catbash" ||
      path === "/catbash/" ||
      path === "/catbash.sh"
    ) {
      return asScript(await asset(env, request, "/catbash.sh"));
    }

    // SICK one-shot hardware script (page is /sick.html)
    if (path === "/sick" || path === "/sick/") {
      return asScript(await asset(env, request, "/hardware_info.sh"));
    }

    // NETS: bare /nets and /nets/ are always the shell script (curl|bash)
    if (path === "/nets" || path === "/nets/") {
      return asScript(await asset(env, request, "/nets/nets.sh"));
    }

    if (path === "/nets.sh" || path === "/nets/nets.sh") {
      return asScript(await asset(env, request, "/nets/nets.sh"));
    }

    // CPUX: Geekbench 5/6/7 runner (page is /cpux.html)
    if (path === "/cpux" || path === "/cpux/" || path === "/cpux.sh") {
      return asScript(await asset(env, request, "/cpux.sh"));
    }

    return env.ASSETS.fetch(request);
  },
};
