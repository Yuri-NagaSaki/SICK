/**
 * catbash.net / 猫脚本 — short install URLs + static site
 *
 * Pages (HTML):
 *   /           → 猫脚本 hub (index.html)
 *   /sick.html  → SICK intro
 *   /nets.html  → NETS intro
 *
 * Scripts (text/plain, curl|bash):
 *   /sick  /sick/  → hardware_info.sh
 *   /nets          → nets/nets.sh
 *   /nets.sh       → nets/nets.sh
 *
 * Note: do NOT serve HTML from /nets/index.html via ASSETS for /nets/ —
 * Workers static assets 307 /nets/index.html → /nets/, which collides with
 * the install short-link. Intro page lives at /nets.html instead.
 *
 * External short links (ba.sh):
 *   https://ba.sh/sick · https://ba.sh/nets
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

    // SICK one-shot hardware script (page is /sick.html)
    if (path === "/sick" || path === "/sick/") {
      return asScript(await asset(env, request, "/hardware_info.sh"));
    }

    // NETS: bare /nets and /nets/ are always the shell script (curl|bash)
    // Trailing slash also script so accidental /nets/ still installs.
    if (path === "/nets" || path === "/nets/") {
      return asScript(await asset(env, request, "/nets/nets.sh"));
    }

    if (path === "/nets.sh") {
      return asScript(await asset(env, request, "/nets/nets.sh"));
    }

    // Force script content-type for the raw file path too
    if (path === "/nets/nets.sh") {
      return asScript(await asset(env, request, "/nets/nets.sh"));
    }

    return env.ASSETS.fetch(request);
  },
};
