import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";
import sidebar from "./src/generated/sidebar.mjs";
import redirects from "./src/generated/redirects.mjs";

// GitHub Pages serves a project repo under a subpath (e.g. /rian-lab). The
// CI workflow passes these from actions/configure-pages; default to root locally.
const base = process.env.BASE_PATH || "/";
const site = process.env.SITE_URL || undefined;

// Astro base-prefixes the redirect SOURCE route but not the target value, so do
// it here (e.g. "/overview/readme/" -> "/rian-lab/overview/readme/")
const prefix = base.replace(/\/$/, "");
const basedRedirects = Object.fromEntries(
  Object.entries(redirects).map(([from, to]) => [from, to.startsWith("/") ? prefix + to : to]),
);

// Astro does NOT base-prefix root-relative links inside Markdown/MDX content,
// and our generated cross-page hrefs are absolute (`/api/...`). This rehype pass
// prepends the deploy base so those links resolve under a Pages subpath. Starlight
// nav/sidebar links are already base-aware; same-page (#) and external links are
// left untouched.
function basePrefix() {
  const prefix = base.replace(/\/$/, "");
  const walk = (node) => {
    if (node && node.type === "element" && node.properties) {
      for (const attr of ["href", "src"]) {
        const v = node.properties[attr];
        if (typeof v === "string" && v[0] === "/" && v[1] !== "/" && !v.startsWith(prefix + "/")) {
          node.properties[attr] = prefix + v;
        }
      }
    }
    node && node.children && node.children.forEach(walk);
  };
  return (tree) => {
    if (prefix) walk(tree);
  };
}

export default defineConfig({
  site,
  base,
  redirects: basedRedirects,
  markdown: { rehypePlugins: [basePrefix] },
  integrations: [
    starlight({
      title: "RianLab",
      sidebar,
      components: { Footer: "./src/components/Footer.astro" },
    }),
  ],
});
