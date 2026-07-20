/**
 * catbash.net / 猫脚本 — short install URLs + static site
 *
 * Pages (HTML):
 *   /           → 猫脚本 hub (index.html)
 *   /sick.html  → SICK intro
 *   /nets/      → NETS intro
 *
 * Scripts (text/plain, curl|bash):
 *   /sick       → hardware_info.sh
 *   /nets       → nets/nets.sh
 *   /nets.sh    → nets/nets.sh
 *
 * External short links (configured on ba.sh, not here):
 *   https://ba.sh/sick → raw/main/hardware_info.sh (or this /sick)
 *   https://ba.sh/nets → raw/main/nets/nets.sh
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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

    // SICK one-shot hardware script (page is /sick.html — no conflict)
    if (path === "/sick" || path === "/sick/") {
      return asScript(await asset(env, request, "/hardware_info.sh"));
    }

    // NETS: bare /nets is always the shell script (curl|bash)
    if (path === "/nets") {
      return asScript(await asset(env, request, "/nets/nets.sh"));
    }

    // /nets/ → landing page
    if (path === "/nets/") {
      const page = await asset(env, request, "/nets/index.html");
      if (page.status === 200) return page;
      return asScript(await asset(env, request, "/nets/nets.sh"));
    }

    // Convenience aliases
    if (path === "/nets.sh" || path === "/nets/nets.sh") {
      return asScript(await asset(env, request, "/nets/nets.sh"));
    }

    return env.ASSETS.fetch(request);
  },
};
