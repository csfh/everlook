# Everlook

A World of Warcraft quality-of-life addon, the harness that runs it outside the game, and its site.

```
addon/    WoW addon and its module addons (Interface/AddOns/Everlook*)
harness/  Lua 5.1 host (Rust) that runs the addon files
www/      Static site (Vite) for Cloudflare Pages. Output is www/dist
```

The addon does not collect world data, sign uploads, or keep a journey. An older saved file loses those keys on load.

## Addon

```sh
lua5.1 addon/tests/run.lua
just test harness
```

`just addon sync` links the addon folders into the game; it reads `EVERLOOK_ADDONS_DIR` from the environment or `.env.local`. See `addon/README.md` and `addon/RELEASING.md`.

Releases are GitHub Releases tagged `addon-v<version>`. A push to `main` that changes `addon/**` runs the addon tests and, when the commits ask for one, publishes that release.

## Site

Cloudflare Pages:

| Setting | Value |
| --- | --- |
| Root directory | `www` |
| Build command | `npm ci && npm run build` |
| Output directory | `dist` |
| Node.js | 22 |

`www/wrangler.toml` sets `pages_build_output_dir` only. Nothing here creates a Cloudflare project or a custom domain.
