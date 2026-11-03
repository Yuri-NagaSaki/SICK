// Refresh the static terminal frames in the HTML pages (what visitors see
// without JS or with prefers-reduced-motion) from assets/demos/*.ansi.
// Uses the same parser/renderer as the in-page player (assets/term.js).
//
//   node tools/demos/render.mjs
//
// A page marks a slot with  <!--demo:NAME-->…<!--/demo-->  inside a
// .term-screen element; everything between the markers is replaced.
import { readFileSync, writeFileSync, existsSync } from "node:fs";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..", "..");
const require = createRequire(import.meta.url);
const T = require(join(root, "assets", "term.js"));

const pages = ["index.html", "sick.html", "nets.html", "cpux.html"];
const slot = /<!--demo:([\w.-]+)-->[\s\S]*?<!--\/demo-->/g;

for (const page of pages) {
  const file = join(root, page);
  if (!existsSync(file)) continue;
  const html = readFileSync(file, "utf8");
  let n = 0;
  const out = html.replace(slot, (all, name) => {
    const src = join(root, "assets", "demos", `${name}.ansi`);
    if (!existsSync(src)) {
      console.warn(`render: ${page}: no ${name}.ansi, slot left as is`);
      return all;
    }
    n++;
    const screen = T.render(readFileSync(src, "utf8"), 40);
    return `<!--demo:${name}-->${T.screenHTML(screen, true)}<!--/demo-->`;
  });
  if (out !== html) writeFileSync(file, out);
  console.log(`render: ${page}: ${n} slot(s)`);
}
