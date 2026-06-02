# AI Website Cloner → Elementor

<a href="https://github.com/Vouanerrio/ai-website-cloner-to-elementor/blob/master/LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License" /></a>

Clone any website into a **fully editable WordPress/Elementor page** using AI. Point it at a URL, run one command, and watch Claude scrape the site, extract every design token, and build the page directly inside your Elementor editor — section by section, using native widgets you can edit, restyle, and reuse.

No static HTML exports. No copy-pasting. A real Elementor page.

**Recommended: [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with Claude Sonnet or Opus**

## How It Works

The `/clone-website --output=elementor` command runs a multi-phase pipeline:

1. **Reconnaissance** — full-page screenshots, design token extraction, interaction sweep (scroll, click, hover, responsive)
2. **Spec Writing** — detailed spec files per section with exact `getComputedStyle()` values, content, assets, and an Elementor widget plan
3. **Foundation** — sets Elementor global colors and typography to match the target site, uploads images to WordPress media library
4. **Elementor Build** — section by section, calls the Elementor MCP to place native widgets: containers, headings, images, buttons, tabs, accordions, card grids, nav menus
5. **Header & Footer** — builds site-wide header and footer using the Header Footer Elementor plugin
6. **Visual QA** — compares the clone against the original, fixes discrepancies, documents known gaps

Each section is built from native Elementor widgets — not HTML blobs — so every element is editable in the Elementor visual editor.

## Also supports Next.js output

The original Next.js clone mode is still fully intact. Run without the flag to get a pixel-perfect Next.js + shadcn/ui codebase instead:

```
/clone-website https://example.com
```

## Quick Start

### Prerequisites

- [Node.js](https://nodejs.org/) 24+
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)
- A WordPress site with [Elementor (free)](https://wordpress.org/plugins/elementor/) installed — local or live
- [Header Footer Elementor](https://wordpress.org/plugins/header-footer-elementor/) plugin (for site-wide header/footer)

### 1. Clone this repo

```bash
git clone https://github.com/YOUR-USERNAME/ai-website-cloner-to-elementor.git
cd ai-website-cloner-to-elementor
npm install
```

### 2. Run the Elementor setup wizard

Run this once per WordPress site. It installs the MCP plugins, wires up authentication, and writes a `.mcp.json` in your project folder:

```bash
bash scripts/setup-elementor-mcp.sh
```

The wizard will ask for:
- Your site type (Local by Flywheel or live host)
- Your WordPress site URL
- Your WordPress username and an [Application Password](https://wordpress.org/documentation/article/application-passwords/)

It will automatically install the two required MCP plugins from GitHub:
- [WordPress MCP Adapter](https://github.com/WordPress/mcp-adapter)
- [MCP Tools for Elementor](https://github.com/msrbuilds/elementor-mcp)

### 3. Restart Claude Code

```bash
claude
```

Approve the `elementor` MCP server when prompted.

### 4. Clone a website to Elementor

```bash
/clone-website --output=elementor https://example.com
```

Watch your WordPress site get built in real time.

## What you get

- A published WordPress page built entirely from native Elementor widgets
- Elementor global colors and typography set to match the target site
- All images uploaded to your WordPress media library
- Site-wide header and footer (requires Header Footer Elementor plugin)
- A `docs/research/ELEMENTOR_GAPS.md` file listing any behaviors that couldn't be reproduced and why

## Known Limitations

Elementor Free has a ceiling. These things won't transfer:

- Scroll-driven animations (parallax, IntersectionObserver fade-ins) — approximated with Elementor's entrance animations
- Smooth scroll libraries (Lenis, Locomotive Scroll)
- CSS `animation-timeline` and scroll-snap
- Elementor Pro features (Theme Builder, Loop Grid, Motion Effects, Popups)

Everything that can't be reproduced is documented in `ELEMENTOR_GAPS.md` so you know exactly what to address manually.

## Multiple pages

Pass multiple URLs to clone several pages in one run:

```bash
/clone-website --output=elementor https://example.com https://example.com/about https://example.com/contact
```

Each becomes a separate WordPress page.

## Project Structure

```
.claude/
  skills/
    clone-website/SKILL.md      # Clone pipeline — Next.js + Elementor modes
    elementor-mcp/SKILL.md      # Elementor widget reference + gotchas
scripts/
  setup-elementor-mcp.sh        # One-time wizard to connect to WordPress
  sync-agent-rules.sh           # Regenerate agent instruction files
  sync-skills.mjs               # Regenerate /clone-website for all platforms
docs/
  research/                     # Spec files, asset map, behavior notes
  design-references/            # Screenshots from target site
src/                            # Next.js scaffold (used in nextjs output mode)
AGENTS.md                       # Agent instructions (single source of truth)
CLAUDE.md                       # Claude Code config
```

## Not Intended For

- **Phishing or impersonation** — must not be used for deceptive purposes or any activity that breaks the law
- **Passing off someone's design as your own** — logos, brand assets, and original copy belong to their owners
- **Violating terms of service** — some sites explicitly prohibit scraping or reproduction. Check first

## Credits

Built on top of two open-source projects:

- **[ai-website-cloner-template](https://github.com/JCodesMore/ai-website-cloner-template)** by [@JCodesMore](https://github.com/JCodesMore) — the original website cloning pipeline
- **[claude-elementor-kit](https://github.com/emersimeon/claude-elementor-kit)** by [@emersimeon](https://github.com/emersimeon) — the Elementor MCP skill and setup wizard
- **[elementor-mcp](https://github.com/msrbuilds/elementor-mcp)** by [@msrbuilds](https://github.com/msrbuilds) — the MCP server that exposes Elementor to AI agents

## License

MIT
