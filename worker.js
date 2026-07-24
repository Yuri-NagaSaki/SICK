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

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const path = url.pathname;

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
