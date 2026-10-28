# Everlook

Quality-of-life addons for World of Warcraft, and the small site that lists them.

```
addon/    The addons: the Everlook core and its Everlook_<Name> modules, with their tests and release scripts
harness/  A Rust host that runs the addon files with the game's frame, mouse and clock rules. It never ships
www/      Static site (Vite) for Cloudflare Pages. Output is www/dist
```

Everlook tweaks the default interface. Each module starts off, and you turn on the ones you want from the Everlook settings page. It collects no data.

## Addon

```sh
just test addon     # Lua suite, script and luac checks
just test harness   # the addon files on the harness (harness/, Rust)
```

`just addon sync` links the addon folders into the game; it reads `EVERLOOK_ADDONS_DIR` from the environment or `.env.local`. See `addon/README.md` and `addon/RELEASING.md`.

Releases are GitHub Releases tagged `addon-v<version>`. A push to `main` that changes `addon/**` runs the addon tests and, when the commits ask for one, publishes that release. A commit outside `addon/` never releases.

## Site

Cloudflare Pages:

| Setting | Value |
| --- | --- |
| Root directory | `www` |
| Build command | `npm ci && npm run build` |
| Output directory | `dist` |
| Node.js | 22 |

The page lists the modules from their TOC files at build time, so a new module shows up on the next build. These settings live in the Pages project, not in a Wrangler file. Nothing here creates a Cloudflare project or a custom domain.
