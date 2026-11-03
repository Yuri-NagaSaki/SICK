"""Local stand-in for the hosts CPUX talks to (run by capture.sh).

  /cdn/<Geekbench-*.tar.gz>   fake Geekbench tarballs from DIR
  /gbb/                       browser.geekbench.com front page (reachability probe)
  /gbb/v*/cpu/<id>[.gbN]      404 "not ready" -> CPUX moves on to the score API
  /api/gb?url=...             {"ok":true,"single":N,"multi":M} (like worker.js)

usage: python3 -I server.py PORT DIR "5:single:multi 6:single:multi ..."
"""
import http.server, os, re, sys, urllib.parse

PORT, DIR = int(sys.argv[1]), sys.argv[2]
SCORES = {}
for item in (sys.argv[3] if len(sys.argv) > 3 else "").split():
    v, s, m = item.split(":")
    SCORES[v] = (int(s), int(m))


class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, code, body, ctype="text/html; charset=utf-8"):
        if isinstance(body, str):
            body = body.encode()
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def do_HEAD(self):
        self.do_GET()

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        p = u.path
        if p.startswith("/cdn/"):
            f = os.path.join(DIR, os.path.basename(p))
            if os.path.isfile(f):
                with open(f, "rb") as fh:
                    return self.send(200, fh.read(), "application/gzip")
            return self.send(404, "not found")
        if p in ("/gbb", "/gbb/"):
            return self.send(200, "<html><title>Geekbench Browser</title></html>")
        if p.startswith("/gbb/"):
            return self.send(404, "<html>Not Found</html>")
        if p == "/api/gb":
            url = urllib.parse.parse_qs(u.query).get("url", [""])[0]
            m = re.search(r"/v(\d)/cpu/\d+", url)
            if m and m.group(1) in SCORES:
                s, mu = SCORES[m.group(1)]
                return self.send(200, '{"ok":true,"single":%d,"multi":%d,"url":"%s"}' % (s, mu, url),
                                 "application/json")
            return self.send(400, '{"ok":false}', "application/json")
        return self.send(404, "not found")


http.server.ThreadingHTTPServer(("127.0.0.1", PORT), H).serve_forever()
