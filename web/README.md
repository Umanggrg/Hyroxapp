# Trakr — Marketing Site

Next.js 14 (App Router) + Tailwind landing page for [Trakr](../README.md). Visually mirrors the iOS app's design system (CLAUDE.md §5) so the site feels like the same product.

## Local development

```bash
cd web
npm install
npm run dev
# → http://localhost:3000
```

Hot reload works for `app/` and `components/` files.

## Project layout

```
web/
├── app/
│   ├── layout.tsx        # <html> shell + metadata + globals.css import
│   ├── page.tsx          # composes the section components
│   └── globals.css       # Tailwind directives + custom CSS (grain, scrollbar, reveal)
├── components/
│   ├── Nav.tsx           # sticky top nav, single CTA
│   ├── Hero.tsx          # hero with headline + RaceCard mock
│   ├── RaceFormatStrip.tsx   # 16-station pill row
│   ├── FeatureGrid.tsx       # 6 feature cards
│   ├── WatchAndDuo.tsx       # two oversize callouts
│   ├── PrivacyPosture.tsx    # privacy-as-positioning section
│   ├── FounderNote.tsx       # first-person founder voice
│   └── Footer.tsx        # TestFlight CTA + legal strip
├── tailwind.config.ts    # Trakr color palette + typography tokens
├── postcss.config.js
├── next.config.mjs
├── tsconfig.json
└── package.json
```

The whole site is one route. Add more under `app/<route>/page.tsx` if you need a privacy page or a press page later.

## Design system

Tokens live in `tailwind.config.ts` and mirror `Hyroxapp/Shared/Theme.swift`:

| Token            | Hex        | Usage                              |
| ---------------- | ---------- | ---------------------------------- |
| `background`     | `#0A0A0B`  | page surface                       |
| `surface`        | `#141416`  | cards                              |
| `surface-elevated` | `#1C1C1F` | tiles inside cards                 |
| `text-primary`   | `#F5F5F7`  | headings, hero numerals            |
| `text-secondary` | `#8E8E93`  | body                               |
| `text-tertiary`  | `#636366`  | meta + caps labels                 |
| `accent`         | `#FF3B30`  | CTAs, glow, active dots            |
| `success`        | `#32D74B`  | PB / on-track signals              |
| `warning`        | `#FF9F0A`  | roxzone / off-pace signals         |
| `divider`        | `#2C2C2E`  | hairlines                          |

Type uses SF Pro Rounded for hero numerals (Tailwind `font-rounded`), SF Pro Text everywhere else (`font-sans`), and a `tabular` utility for live numbers — same monospaced-digit pattern the app uses to prevent jitter.

## Deploy

Easiest path is **Vercel**:

1. `npm i -g vercel` (one-time)
2. From this folder: `vercel`
3. Accept the defaults. The first deploy gives you a `*.vercel.app` URL; you can attach `trakr.app` (or any custom domain) afterward.

Alternatively, **Cloudflare Pages**, **Netlify**, **Render** — all support Next.js 14 with zero config. Or `npm run build && npm run start` on any Node host.

## TestFlight email capture

The form in `Footer.tsx` currently uses a `mailto:` action as a no-server placeholder. Before launch, swap this for a real handler — options ranked by effort:

1. **Formspree / Tally** — paste an endpoint into the form `action`; ~5 minutes.
2. **Vercel route handler** — `app/api/invite/route.ts` writes to Supabase or sends via Resend; ~30 minutes.
3. **Direct Supabase** (when v1 backend is live) — already in the stack; just an `insert` into a `signups` table.

## Notes

- `themeColor` is set to `#0A0A0B` so the iOS Safari address bar matches the page background — small touch, big difference.
- Reduced-motion users get static reveals automatically (`@media (prefers-reduced-motion: reduce)` in `globals.css`).
- The privacy section currently links to `https://github.com` as a placeholder — point it at the hosted `docs/PRIVACY.md` once that's live (GitHub Pages is fine).
