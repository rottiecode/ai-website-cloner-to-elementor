---
name: elementor-mcp
description: Helps with WordPress + Elementor work via the elementor-mcp MCP server — building new pages, editing existing ones, inspecting site state, or exploring what's possible. Asks what the user wants before acting. Use when the user references the Elementor MCP, invokes `/elementor-mcp`, or runs `mcp__elementor__elementor-mcp-*` tools. Also covers initial install of the MCP Adapter + elementor-mcp plugins, app-password auth wiring, schema-loading discipline, and the widget-vs-HTML decision tree. SKIP for Bricks, Divi, Beaver Builder, or non-Elementor WordPress builds.
---

# Elementor MCP Skill

You are operating against a WordPress site with the **elementor-mcp** server (`https://github.com/msrbuilds/elementor-mcp`) connected via the WordPress MCP Adapter. This skill captures everything I learned the hard way the first time through, so subsequent sessions start at expertise level.

## 🛑 First Action Protocol — ASK BEFORE DOING

**When this skill is invoked, do not start running tools. Ask the user what they want first.**

If the user's invocation message *already* contains a clear task — *"build me a hero section from `index.html`"*, *"show me my current global colors"*, *"change the burgundy to navy"* — proceed with that task directly.

Otherwise *(invocations like `/elementor-mcp` alone, or "use the Elementor MCP" with no follow-up)*, **respond with this menu and wait for the user to pick:**

```
What would you like to do with your Elementor site?

  1. Build       — create new pages or sections from a design
  2. Edit        — change something on an existing page
  3. Reference   — inspect current state (pages, colors, fonts, content)
  4. Explore     — show me what's possible / what can the MCP do here
```

Do **not** silently default to "build" — that's the most destructive action and forces a path the user may not want. Wait for the user to choose 1/2/3/4 *(or describe their task in their own words)* before invoking any MCP tool other than the harmless read-only ones at the bottom of this section.

### Read-only "smoke test" calls that are always safe to run

When the user picks any option, you can run these **before** asking follow-up questions, since they help frame the next response:

- `mcp__elementor__elementor-mcp-list-pages` — confirms auth + lists what's there
- `mcp__elementor__elementor-mcp-get-global-settings` — current colors/fonts kit

That's it for unprompted tool calls. **Anything that creates, modifies, or deletes data requires the user to have explicitly asked for it.**

## When this skill applies

- The user mentions Elementor MCP, types `/elementor-mcp`, or says "use the Elementor MCP"
- A `.mcp.json` in the project registers an MCP server pointing at `wp-json/mcp/elementor-mcp-server`
- The user asks to build, edit, inspect, or troubleshoot an Elementor page
- Tools beginning with `mcp__elementor__elementor-mcp-*` are available

## First-session setup (when MCP not yet connected)

If the user has a WordPress site but no `.mcp.json` and no `elementor` MCP loaded:

1. **Check whether they're using Local-by-Flywheel or a live host.** Setup paths differ.
2. **Run the bundled setup script** at `scripts/setup-elementor-mcp.sh` — it handles plugin install, auth wiring, and `.mcp.json` generation interactively for both flavors.
   ```bash
   bash scripts/setup-elementor-mcp.sh
   ```
3. After the script completes, instruct the user to **quit and reopen Claude Code in the project directory** so the new `.mcp.json` is picked up.
4. On reopen, the deferred MCP tools will be exposed via ToolSearch — load the ones you need with `select:` queries.

If something fails, see "Setup gotchas" below.

## Working session conventions

### Always do this first

```
mcp__elementor__elementor-mcp-list-pages   # confirms auth + lists existing pages
mcp__elementor__elementor-mcp-get-global-settings   # see existing colors/fonts kit
mcp__elementor__elementor-mcp-get-container-schema  # ground truth on flex_* key names
```

The container schema is large (~50KB). Read it once, then write down the keys you'll use in your reply text so you don't need to re-fetch it. Critical keys:

- `flex_direction`, `flex_justify_content`, `flex_align_items`, `flex_gap`, `flex_wrap` — note the **`flex_` prefix** on justify/align
- `content_width: "boxed"|"full"` + `boxed_width: {unit, size, sizes}`
- `min_height: {unit, size, sizes}` — use unit `vh` for full-screen heroes
- `padding`/`margin: {unit, top, right, bottom, left, isLinked}` — `isLinked: false` when sides differ
- `background_background: "classic"|"gradient"|"video"` — must be set first or other background_* keys are ignored
- `background_overlay_opacity: {unit:"px", size: 0.5}` (yes, the unit is `px` even for opacity — quirk of the schema)

### Widget call convention — flat params, NOT nested in `settings`

```js
// ✓ CORRECT
mcp__elementor__elementor-mcp-add-heading({
  post_id: 11,
  parent_id: "abc123",
  title: "where estates <em>are entrusted</em>",
  header_size: "h1",
  title_color: "#FFFFFF",
  typography_typography: "custom",       // ← required to enable typography
  typography_font_family: "Cormorant Garamond",
  typography_font_size: {size: 110, unit: "px"},
  typography_font_weight: "300",
  typography_line_height: {size: 0.98, unit: "em"},
})

// ✗ WRONG — silently fails or returns "title is required"
mcp__elementor__elementor-mcp-add-heading({
  post_id: 11,
  parent_id: "abc123",
  settings: {title: "...", typography_font_family: "..."}
})
```

`add-container` is the **exception** — it takes a `settings: {}` object. Don't generalize from one to the other.

### Always set `typography_typography: "custom"`

Without this, the other typography_* keys are ignored. Same applies to `css_filters_css_filter: "custom"` for image filters, etc.

### Italic emphasis pattern

Display headings often need a single italic-emphasized word. Don't use a separate widget — just inline `<em>` in the title:

```js
title: "A <em>quiet</em> practice for an <em>uncommon</em> clientele."
```

## The widget-vs-HTML decision — DEFAULT TO NATIVE WIDGETS

> 🚨 **CRITICAL ANTI-PATTERN — read this first.**
>
> **Do NOT paste an entire HTML page into one HTML widget.** Do NOT build a homepage that is "1 container with 3 HTML widgets inside." That is not building with Elementor — that is using Elementor as a wrapper around a static webpage. The user **cannot edit it** in the Elementor visual editor, **cannot reuse the design tokens**, and **cannot iterate** on it without going back to source code.

### Always default to native widgets

- **Headings** → `add-heading` widget
- **Body copy** → `add-text-editor` widget
- **Images** → `add-image` widget
- **Buttons / CTAs** → `add-button` widget
- **Layout / spacing** → `add-container` with proper `flex_*` settings
- **Lists** → `add-icon-list` widget
- **Tabs** → `add-tabs` widget
- **Accordions / FAQs** → `add-accordion` widget
- **Forms** → Fluent Forms shortcode via `add-shortcode` widget
- **Nav menu in headers** → UAE Nav Menu widget (`uael-nav-menu`)

### When HTML widget IS allowed *(narrow list — exceptions only)*

1. **Tab/accordion content with rich layout.** `add-tabs` only accepts `tab_content` as a string of HTML, so a multi-card grid inside a tab MUST be HTML. *(But the wrapping Tabs widget itself is still native.)*
2. **Decorative-only flourishes** with no native equivalent — a thin gold rule with a CSS-pseudo-element flourish, an animated underline, a gradient overlay on a child element.
3. **Form HTML as a flagged placeholder** when no real form plugin is wired up yet — and you must explicitly tell the user "form is visual only, doesn't capture submissions."
4. **Site-wide CSS overrides** scoped to a specific Elementor element ID. These should be small `<style>`-only blocks, not whole sections of markup.

### What about card grids of 4+ items?

Build the first card with native widgets *(Container → Image → Heading → Text Editor → Button)*, use `duplicate-element` to copy it N times, then `update-element` to change the copy/image on each duplicate. Wrap them in a parent Container with `flex_direction: row` and `flex_wrap: wrap`.

### Cross-widget styling — `<style>`-only HTML widgets

When you need to style a native widget from outside, use a **`<style>`-only HTML widget** — it contains ONLY a `<style>` block, no markup:

```html
<style>
.elementor-element-f8d1545 .elementor-tab-title {
  text-transform: uppercase !important;
  letter-spacing: .26em !important;
}
</style>
```

## When the user asks to BUILD — building order

1. `update-global-colors` + `update-global-typography` — establish design tokens
2. `create-page({title, status: "publish", template: "elementor_canvas"})` — Canvas template removes theme header/footer chrome
3. (Via WP-CLI) Set as static front page: `wp option update show_on_front page; wp option update page_on_front <id>`
4. Build sections — outer container → inner content container (boxed, max-width 1360px-ish) → content
5. After each section: `get-page-structure(post_id)` to verify nesting
6. **Pause for human review** before building header/footer

## When the user asks to EDIT

1. `list-pages` to find the page
2. `get-page-structure(post_id)` to see the widget tree and grab element IDs
3. Use `find-element` if needed, then `update-element` with only the fields that change
4. Verify by re-reading `get-page-structure`
5. **Never delete a section unless they explicitly ask**

## When the user asks to REFERENCE / INSPECT

- `list-pages` — what pages exist
- `get-global-settings` — colors, typography, layout settings
- `get-page-structure(post_id)` — what's on a page
- `get-element-settings(element_id)` — exact settings of one widget
- `find-element(post_id, ...)` — locate a widget by content/type

## Header/Footer notes

The MCP plugin's `create-theme-template` tool requires **Elementor Pro**. With Elementor Free, headers and footers are built using **Ultimate Addons for Elementor (UAE)** or **Header Footer Elementor (HFE)** — both share the same `elementor-hf` post type.

### Building a site-wide header

1. **Create the WordPress menu first.** WP Admin → Appearance → Menus, name it "Main", add pages, save. The MCP cannot create WP nav menus.
2. **Create the header template post** with `post_type: "elementor-hf"` and set meta: `ehf_template_type = "type_header"`, `display-on-canvas = "yes"`.
3. **Build the layout:** logo + UAE Nav Menu widget (`uael-nav-menu`) pointed at the menu by name + CTA button.
4. **Verify display:** WP Admin → Appearance → Header Footer Builder → Display On: Entire Website.

### Footer pattern

Same `post_type: "elementor-hf"` but `ehf_template_type = "type_footer"`. Typically a 4-column container (brand block + 3 link columns) with a bottom row for copyright + social icons.

### Forms — Fluent Forms

**The user does (manual, ~2-3 min):**
1. Fluent Forms → New Form → Contact Form template → Save → note the form ID

**Claude does:**
1. `add-shortcode` widget with `[fluentform id="<ID>"]`
2. Add a `<style>`-only HTML widget alongside to style the form

## Setup gotchas

- **The application password's *label* is not the username.** The WP username remains `admin` or whatever they set up. If auth fails, check `GET /wp-json/wp/v2/users` to find the real slug.
- **Local-by-Flywheel `wp-config.php` says `DB_HOST=localhost`** but the real MySQL is on a per-site Unix socket. The setup script handles this automatically.
- **Neither MCP plugin is on wordpress.org.** Cannot install via REST API by slug — the setup script downloads from GitHub Releases.
- **Claude Code only loads `.mcp.json` at startup** — after writing one, the user must quit and reopen.
- **The `detect-elementor-version` tool errors** in some versions. Use `list-pages` for the auth-works check instead.

## Live-host vs Local differences

**Local-by-Flywheel:** Plugin install via the bundled WP-CLI binary. The setup script automates all of this.

**Live host:** Plugin install via WP Admin → Plugins → Add New → Upload Plugin (manual upload of the two zips). Auth is the same — REST API + Application Password.

## Tool-loading discipline

The MCP exposes ~75 deferred tools. Don't load them all at once — fetch schemas lazily:

- **First call:** `list-pages`
- **Before building containers:** load `get-container-schema`, `add-container`, `update-container`
- **Before placing widgets:** load `add-heading`, `add-text-editor`, `add-button`, `add-image`, `add-html` in one batch
- **Before specific widgets:** load `add-tabs`, `add-icon-list`, `add-divider`, `add-spacer` as needed

Use `ToolSearch` query format `select:tool1,tool2,tool3` to load multiple in one call.

## What the MCP cannot do

- Install plugins or themes (use WP-CLI or WP Admin instead)
- Set the static front page (use `wp option update`)
- Build a custom header/footer on Elementor Free without the HFE plugin
- Create WordPress nav menus (must be done manually in WP Admin)
- Pixel-perfect parity with hand-coded HTML — Elementor's flexbox container model is the ceiling

## Quick reference — the build flow

```
1. bash scripts/setup-elementor-mcp.sh   # one-time, ~3 minutes
2. Quit + reopen Claude Code             # picks up .mcp.json
3. list-pages                            # confirm auth
4. get-global-settings                   # see current kit
5. update-global-colors + typography
6. create-page (Elementor Canvas template)
7. Set as front page via WP-CLI
8. Build sections top-down, one at a time
9. After each: get-page-structure or curl the front page
10. Pause for human review before header/footer
```
