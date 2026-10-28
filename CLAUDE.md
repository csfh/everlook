@AGENTS.md

## Design

Every visible change in `www/` is a design decision. Settle hierarchy, layout, typography, color, spacing, states, accessibility and copy before writing code. The addon's own surfaces follow the Direction in `addon/AGENTS.md`.

## Skills

Load the skill for the work before starting it, and always for UI work. Skills live in `~/.agents/skills`, linked into `~/.claude/skills`.

| Work | Skill |
| --- | --- |
| Building or reviewing the site's UI | `better-interface`, or the focused `better-layout`, `better-typography`, `better-colors`, `better-ui`, `better-accessibility`, `better-writing` |
| Assessing an existing screen | `interface-review`, `explain-interface` |
| Motion and polish | `animate`, `emil-design-eng`, `apple-design`, `review-animations`, `improve-animations`, `find-animation-opportunities` |
| Touch and small screens | `mobile-native` |
| Choosing a library for the site, which is vanilla Vite | `pick-ui-library` |
| Implementing, refactoring, committing | `swe`, with `tdd` for test-first work |
| Something broken | `diagnosing-bugs` |
| Editing `AGENTS.md`, `CLAUDE.md` or a skill | `writing-for-agents` |
| The license, CLA or contributing guide | `oss` |
