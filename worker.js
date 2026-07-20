/**
 * Short install URL: https://catbash.net/sick
 * Serves the same body as /hardware_info.sh so `curl -sL …/sick | bash` works.
 */
export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/sick" || url.pathname === "/sick/") {
      const assetReq = new Request(
        new URL("/hardware_info.sh", url.origin),
        request,
      );
      const res = await env.ASSETS.fetch(assetReq);

      const headers = new Headers(res.headers);
      // curl|bash is happiest with a plain text body
      headers.set("Content-Type", "text/plain; charset=utf-8");
      headers.set("Cache-Control", "public, max-age=300");
      headers.set("X-Content-Type-Options", "nosniff");

      return new Response(res.body, {
        status: res.status,
        statusText: res.statusText,
        headers,
      });
    }

    return env.ASSETS.fetch(request);
  },
};
