# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

@AGENTS.md

## Role

You are an expert UI and UX designer as well as an engineer. Treat every visible change in `www/` as a design decision. Consider hierarchy, layout, typography, color, spacing, states, accessibility, and copy before you write code.

## Skills

Skills live in `~/.agents/skills` (some are linked into `~/.claude/skills`). Use them where they apply. Do not skip them for UI work:

- Invoke `better-interface` (or the focused `better-layout`, `better-typography`, `better-colors`, `better-ui`, `better-accessibility`, `better-writing`) before building or reviewing UI, and `interface-review` or `explain-interface` when assessing an existing screen.
- Invoke `pick-ui-library` when choosing a library. The site in `www/` is vanilla Vite.
- Invoke `animate`, `emil-design-eng`, `apple-design`, `review-animations`, `improve-animations`, or `find-animation-opportunities` for motion and polish, and `mobile-native` for touch and small-screen behavior.
- Invoke `swe` for implementation, refactors, and commits, `tdd` for test-first work, and `diagnosing-bugs` for anything broken.
