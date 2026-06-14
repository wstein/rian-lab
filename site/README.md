# RianLab site

Two surfaces live here, sharing one brand layer:

1. **Reference docs** — an [Astro](https://astro.build) + [Starlight](https://starlight.astro.build)
   site whose content is **generated**, not authored. `mix docs` (via `Rian.DocFormatter`) emits
   site-ready MDX + sidebar + redirects into `../doc/`; `npm run sync` copies them into
   `src/content/docs/` and `src/generated/` (both gitignored). Do not hand-edit those — change the
   ADRs/specs/moduledocs and regenerate.

2. **Bespoke pages** — the marketing/tutorial surface in `src/pages/`, recreated from the Claude
   Design handoff:

   | Route | File | What it is |
   | --- | --- | --- |
   | `/home` | `pages/home.astro` | landing: dual-lowering hero, why-Rian, pipeline, target matrix |
   | `/by-example` | `pages/by-example.astro` | the runnable four-target tour |
   | `/playground` | `pages/playground.astro` | IDE shell over the tour examples |
   | `/docs-reader` | `pages/docs-reader.astro` | curated ADR reader → links into the Starlight reference |
   | `/contributors` | `pages/contributors.astro` | the ADR-as-unit-of-change model |

   They share `layouts/SiteShell.astro` (brand nav, persisted light/dark theme, footer),
   `styles/rian-site.css` (the design tokens), `lib/highlight.ts` (a small build-time highlighter),
   and the components in `components/site/`.

## The tour dataset

Every per-target code block on the bespoke pages comes from **`src/data/tour.json`** — it is *not*
hand-written. `mix rian.tour` (in the repo root) runs the real Rust/JS/Kotlin emitters and the
reachability analysis over the curated tour programs and writes that file, so the site cannot drift
from the compiler. `Rian.TourTest` fails CI if the committed file is stale; regenerate with:

```sh
mix rian.tour        # from the repo root
```

## Develop / build

```sh
cd site
npm install
npm run dev          # predev runs `npm run sync` (needs `mix docs` to have produced ../doc)
npm run build        # prebuild syncs, then `astro build`
```

`/` redirects to the generated docs; the bespoke pages are reached at the routes above. (To make the
homepage the site root, repoint the formatter's root redirect — a deliberate follow-up, not wired
here.)
