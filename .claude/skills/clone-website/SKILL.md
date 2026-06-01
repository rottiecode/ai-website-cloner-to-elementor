---
name: clone-website
description: Reverse-engineer and clone one or more websites in one shot — extracts assets, CSS, and content section-by-section and proactively dispatches parallel builder agents in worktrees as it goes. Use this whenever the user wants to clone, replicate, rebuild, reverse-engineer, or copy any website. Also triggers on phrases like "make a copy of this site", "rebuild this page", "pixel-perfect clone". Provide one or more target URLs as arguments. Optionally add --output=elementor to build the clone as a fully editable Elementor/WordPress page instead of Next.js.
argument-hint: "[--output=elementor] <url1> [<url2> ...]"
user-invocable: true
---

# Clone Website

## Output Mode Detection

Parse `$ARGUMENTS` first. If it contains `--output=elementor`, set **OUTPUT_MODE = elementor** and strip that flag from the URL list. Otherwise, **OUTPUT_MODE = nextjs** (default).

- **nextjs mode** — builds a pixel-perfect Next.js + shadcn/ui clone (original behavior, unchanged)
- **elementor mode** — clones the site into a fully editable WordPress/Elementor page using native widgets; no React code is produced

The reconnaissance and spec-writing phases are **identical in both modes** — only Phase 2 onward diverges. Read the relevant phase sections for your active mode.

---

You are about to reverse-engineer and rebuild **$ARGUMENTS** as pixel-perfect clones.

When multiple URLs are provided, process them independently and in parallel where possible, while keeping each site's extraction artifacts isolated in dedicated folders (for example, `docs/research/<hostname>/`).

This is not a two-phase process (inspect then build). You are a **foreman walking the job site** — as you inspect each section of the page, you write a detailed specification to a file, then hand that file to a specialist builder agent with everything they need. Extraction and construction happen in parallel, but extraction is meticulous and produces auditable artifacts.

## Scope Defaults

The target is whatever page `$ARGUMENTS` resolves to. Clone exactly what's visible at that URL. Unless the user specifies otherwise, use these defaults:

- **Fidelity level:** Pixel-perfect — exact match in colors, spacing, typography, animations
- **In scope:** Visual layout and styling, component structure and interactions, responsive design, mock data for demo purposes
- **Out of scope:** Real backend / database, authentication, real-time features, SEO optimization, accessibility audit
- **Customization:** None — pure emulation

**Elementor mode fidelity note:** Full pixel-perfect parity is not achievable in Elementor. The goal is a structurally faithful, fully editable page — Elementor's flexbox container model is the ceiling. Complex CSS animations, scroll-driven behaviors, and parallax effects are documented in specs but approximated in the build. The user gets an editable page, not a static export.

If the user provides additional instructions (specific fidelity level, customizations, extra context), honor those over the defaults.

## Pre-Flight

### Both modes

1. **Browser automation is required.** Check for available browser MCP tools (Chrome MCP, Playwright MCP, Browserbase MCP, Puppeteer MCP, etc.). Use whichever is available — if multiple exist, prefer Chrome MCP. If none are detected, ask the user which browser tool they have and how to connect it. This skill cannot work without browser automation.
2. Parse `$ARGUMENTS` (after stripping `--output=elementor` if present) as one or more URLs. Normalize and validate each URL; if any are invalid, ask the user to correct them before proceeding. For each valid URL, verify it is accessible via your browser MCP tool.
3. Create the output directories if they don't exist: `docs/research/`, `docs/research/components/`, `docs/design-references/`, `scripts/`. For multiple clones, also prepare per-site folders like `docs/research/<hostname>/` and `docs/design-references/<hostname>/`.
4. When working with multiple sites in one command, optionally confirm whether to run them in parallel (recommended, if resources allow) or sequentially to avoid overload.

### Next.js mode only

5. Verify the base project builds: `npm run build`. The Next.js + shadcn/ui + Tailwind v4 scaffold should already be in place. If not, tell the user to set it up first.

### Elementor mode only

5. **Verify Elementor MCP is connected.** Check that tools beginning with `mcp__elementor__elementor-mcp-*` are available. If not, tell the user to run the setup wizard first:
   ```bash
   bash ~/.claude/scripts/setup-elementor-mcp.sh
   ```
   Then quit and reopen Claude Code in the project directory so `.mcp.json` is picked up.
6. Run a smoke test to confirm auth and see the current site state:
   - `mcp__elementor__elementor-mcp-list-pages` — confirms auth + lists existing pages
   - `mcp__elementor__elementor-mcp-get-global-settings` — current colors/fonts kit
7. **Note on assets:** Downloaded images cannot live in `public/` for WordPress. You will upload them to the WordPress media library via WP-CLI or WP Admin → Media → Add New during Phase 2. Keep track of every image URL and its resulting WordPress attachment ID — you'll need the IDs for `add-image` widget calls.

## Guiding Principles

These are the truths that separate a successful clone from a "close enough" mess. Internalize them — they should inform every decision you make.

### 1. Completeness Beats Speed

Every builder agent (Next.js) or widget-build sequence (Elementor) must receive **everything** it needs to do its job perfectly: screenshot, exact CSS values, downloaded assets with local paths, real text content, component structure. If a builder has to guess anything — a color, a font size, a padding value — you have failed at extraction. Take the extra minute to extract one more property rather than shipping an incomplete brief.

### 2. Small Tasks, Perfect Results

When an agent gets "build the entire features section," it glosses over details — it approximates spacing, guesses font sizes, and produces something "close enough" but clearly wrong. When it gets a single focused component with exact CSS values, it nails it every time.

Look at each section and judge its complexity. A simple banner with a heading and a button? One agent. A complex section with 3 different card variants, each with unique hover states and internal layouts? One agent per card variant plus one for the section wrapper. When in doubt, make it smaller.

**Complexity budget rule:** If a builder prompt exceeds ~150 lines of spec content, the section is too complex for one agent. Break it into smaller pieces. This is a mechanical check — don't override it with "but it's all related."

### 3. Real Content, Real Assets

Extract the actual text, images, videos, and SVGs from the live site. This is a clone, not a mockup. Use `element.textContent`, download every `<img>` and `<video>`, extract inline `<svg>` elements. The only time you generate content is when something is clearly server-generated and unique per session.

**Layered assets matter.** A section that looks like one image is often multiple layers — a background watercolor/gradient, a foreground UI mockup PNG, an overlay icon. Inspect each container's full DOM tree and enumerate ALL `<img>` elements and background images within it, including absolutely-positioned overlays. Missing an overlay image makes the clone look empty even if the background is correct.

### 4. Foundation First

Nothing can be built until the foundation exists: global colors, fonts, and assets. This is sequential and non-negotiable. Everything after this can be parallel (Next.js) or section-by-section (Elementor).

### 5. Extract How It Looks AND How It Behaves

A website is not a screenshot — it's a living thing. Elements move, change, appear, and disappear in response to scrolling, hovering, clicking, resizing, and time. If you only extract the static CSS of each element, your clone will look right in a screenshot but feel dead when someone actually uses it.

For every element, extract its **appearance** (exact computed CSS via `getComputedStyle()`) AND its **behavior** (what changes, what triggers the change, and how the transition happens). Not "it looks like 16px" — extract the actual computed value. Not "the nav changes on scroll" — document the exact trigger (scroll position, IntersectionObserver threshold, viewport intersection), the before and after states (both sets of CSS values), and the transition (duration, easing, CSS transition vs. JS-driven vs. CSS `animation-timeline`).

Examples of behaviors to watch for — these are illustrative, not exhaustive. The page may do things not on this list, and you must catch those too:
- A navbar that shrinks, changes background, or gains a shadow after scrolling past a threshold
- Elements that animate into view when they enter the viewport (fade-up, slide-in, stagger delays)
- Sections that snap into place on scroll (`scroll-snap-type`)
- Parallax layers that move at different rates than the scroll
- Hover states that animate (not just change — the transition duration and easing matter)
- Dropdowns, modals, accordions with enter/exit animations
- Scroll-driven progress indicators or opacity transitions
- Auto-playing carousels or cycling content
- Dark-to-light (or any theme) transitions between page sections
- **Tabbed/pill content that cycles** — buttons that switch visible card sets with transitions
- **Scroll-driven tab/accordion switching** — sidebars where the active item auto-changes as content scrolls past (IntersectionObserver, NOT click handlers)
- **Smooth scroll libraries** (Lenis, Locomotive Scroll) — check for `.lenis` class or scroll container wrappers

### 6. Identify the Interaction Model Before Building

This is the single most expensive mistake in cloning: building a click-based UI when the original is scroll-driven, or vice versa. Before writing any builder prompt for an interactive section, you must definitively answer: **Is this section driven by clicks, scrolls, hovers, time, or some combination?**

How to determine this:
1. **Don't click first.** Scroll through the section slowly and observe if things change on their own as you scroll.
2. If they do, it's scroll-driven. Extract the mechanism: `IntersectionObserver`, `scroll-snap`, `position: sticky`, `animation-timeline`, or JS scroll listeners.
3. If nothing changes on scroll, THEN click/hover to test for click/hover-driven interactivity.
4. Document the interaction model explicitly in the component spec: "INTERACTION MODEL: scroll-driven with IntersectionObserver" or "INTERACTION MODEL: click-to-switch with opacity transition."

A section with a sticky sidebar and scrolling content panels is fundamentally different from a tabbed interface where clicking switches content. Getting this wrong means a complete rewrite, not a CSS tweak.

### 7. Extract Every State, Not Just the Default

Many components have multiple visual states — a tab bar shows different cards per tab, a header looks different at scroll position 0 vs 100, a card has hover effects. You must extract ALL states, not just whatever is visible on page load.

For tabbed/stateful content:
- Click each tab/button via browser MCP
- Extract the content, images, and card data for EACH state
- Record which content belongs to which state
- Note the transition animation between states (opacity, slide, fade, etc.)

For scroll-dependent elements:
- Capture computed styles at scroll position 0 (initial state)
- Scroll past the trigger threshold and capture computed styles again (scrolled state)
- Diff the two to identify exactly which CSS properties change
- Record the transition CSS (duration, easing, properties)
- Record the exact trigger threshold (scroll position in px, or viewport intersection ratio)

### 8. Spec Files Are the Source of Truth

Every component gets a specification file in `docs/research/components/` BEFORE any builder is dispatched (Next.js) or widget sequence begins (Elementor). This file is the contract between your extraction work and the build phase. The file persists as an auditable artifact that the user (or you) can review if something looks wrong.

The spec file is not optional. It is not a nice-to-have. If you start building without first writing a spec file, you are working from memory, and you will guess to fill gaps.

### 9. Next.js: Build Must Always Compile

*(Next.js mode only)* Every builder agent must verify `npx tsc --noEmit` passes before finishing. After merging worktrees, you verify `npm run build` passes. A broken build is never acceptable, even temporarily.

### 10. Elementor: Default to Native Widgets, Never HTML Blobs

*(Elementor mode only)* **Do NOT paste a whole section as a single HTML widget.** That produces a non-editable static export, which defeats the entire purpose of this output mode. Every section must be built from native Elementor widgets. The HTML widget is reserved for four narrow exceptions only — see the Elementor Anti-Patterns section below.

---

## Phase 1: Reconnaissance

*(Identical in both modes)*

Navigate to the target URL with browser MCP.

### Screenshots
- Take **full-page screenshots** at desktop (1440px) and mobile (390px) viewports
- Save to `docs/design-references/` with descriptive names
- These are your master reference — builders will receive section-specific crops/screenshots later

### Global Extraction
Extract these from the page before doing anything else:

**Fonts** — Inspect `<link>` tags for Google Fonts or self-hosted fonts. Check computed `font-family` on key elements (headings, body, code, labels). Document every family, weight, and style actually used.

**Colors** — Extract the site's color palette from computed styles across the page. Build a named palette: primary, secondary, accent, background, text, muted, etc. Record exact hex/rgb values.

**Favicons & Meta** — Download favicons, apple-touch-icons, OG images to `docs/design-references/seo/`.

**Global UI patterns** — Identify any site-wide CSS or JS: custom scrollbar hiding, scroll-snap on the page container, global keyframe animations, backdrop filters, gradients used as overlays, **smooth scroll libraries** (Lenis, Locomotive Scroll — check for `.lenis`, `.locomotive-scroll`, or custom scroll container classes).

### Mandatory Interaction Sweep

This is a dedicated pass AFTER screenshots and BEFORE anything else. Its purpose is to discover every behavior on the page — many of which are invisible in a static screenshot.

**Scroll sweep:** Scroll the page slowly from top to bottom via browser MCP. At each section, pause and observe:
- Does the header change appearance? Record the scroll position where it triggers.
- Do elements animate into view? Record which ones and the animation type.
- Does a sidebar or tab indicator auto-switch as you scroll? Record the mechanism.
- Are there scroll-snap points? Record which containers.
- Is there a smooth scroll library active? Check for non-native scroll behavior.

**Click sweep:** Click every element that looks interactive:
- Every button, tab, pill, link, card
- Record what happens: does content change? Does a modal open? Does a dropdown appear?
- For tabs/pills: click EACH ONE and record the content that appears for each state

**Hover sweep:** Hover over every element that might have hover states:
- Buttons, cards, links, images, nav items
- Record what changes: color, scale, shadow, underline, opacity

**Responsive sweep:** Test at 3 viewport widths via browser MCP:
- Desktop: 1440px
- Tablet: 768px
- Mobile: 390px
- At each width, note which sections change layout (column → stack, sidebar disappears, etc.) and at approximately which breakpoint the change occurs.

Save all findings to `docs/research/BEHAVIORS.md`. This is your behavior bible — reference it when writing every component spec.

### Page Topology
Map out every distinct section of the page from top to bottom. Give each a working name. Document:
- Their visual order
- Which are fixed/sticky overlays vs. flow content
- The overall page layout (scroll container, column structure, z-index layers)
- Dependencies between sections (e.g., a floating nav that overlays everything)
- **The interaction model** of each section (static, click-driven, scroll-driven, time-driven)

Save this as `docs/research/PAGE_TOPOLOGY.md` — it becomes your assembly blueprint.

---

## Phase 2: Foundation Build

### Next.js mode

This is sequential. Do it yourself (not delegated to an agent) since it touches many files:

1. **Update fonts** in `layout.tsx` to match the target site's actual fonts
2. **Update globals.css** with the target's color tokens, spacing values, keyframe animations, utility classes, and any **global scroll behaviors** (Lenis, smooth scroll CSS, scroll-snap on body)
3. **Create TypeScript interfaces** in `src/types/` for the content structures you've observed
4. **Extract SVG icons** — find all inline `<svg>` elements on the page, deduplicate them, and save as named React components in `src/components/icons.tsx`. Name them by visual function (e.g., `SearchIcon`, `ArrowRightIcon`, `LogoIcon`).
5. **Download global assets** — write and run a Node.js script (`scripts/download-assets.mjs`) that downloads all images, videos, and other binary assets from the page to `public/`. Preserve meaningful directory structure.
6. Verify: `npm run build` passes

#### Asset Discovery Script Pattern

Use browser MCP to enumerate all assets on the page:

```javascript
JSON.stringify({
  images: [...document.querySelectorAll('img')].map(img => ({
    src: img.src || img.currentSrc,
    alt: img.alt,
    width: img.naturalWidth,
    height: img.naturalHeight,
    parentClasses: img.parentElement?.className,
    siblings: img.parentElement ? [...img.parentElement.querySelectorAll('img')].length : 0,
    position: getComputedStyle(img).position,
    zIndex: getComputedStyle(img).zIndex
  })),
  videos: [...document.querySelectorAll('video')].map(v => ({
    src: v.src || v.querySelector('source')?.src,
    poster: v.poster,
    autoplay: v.autoplay,
    loop: v.loop,
    muted: v.muted
  })),
  backgroundImages: [...document.querySelectorAll('*')].filter(el => {
    const bg = getComputedStyle(el).backgroundImage;
    return bg && bg !== 'none';
  }).map(el => ({
    url: getComputedStyle(el).backgroundImage,
    element: el.tagName + '.' + el.className?.split(' ')[0]
  })),
  svgCount: document.querySelectorAll('svg').length,
  fonts: [...new Set([...document.querySelectorAll('*')].slice(0, 200).map(el => getComputedStyle(el).fontFamily))],
  favicons: [...document.querySelectorAll('link[rel*="icon"]')].map(l => ({ href: l.href, sizes: l.sizes?.toString() }))
});
```

Then write a download script that fetches everything to `public/`. Use batched parallel downloads (4 at a time) with proper error handling.

---

### Elementor mode

This is sequential. Do it yourself since it touches global site settings:

1. **Download all assets** using the same asset discovery script above, saving to a local `docs/assets/` folder. These will be uploaded to WordPress.

2. **Upload images to WordPress media library.** For a local site (Local by Flywheel), use WP-CLI:
   ```bash
   # Upload each image and capture the returned attachment ID
   wp media import /path/to/image.jpg --title="Hero Background" --porcelain
   # Returns an integer ID — record it alongside the original URL
   ```
   For a live host, upload via WP Admin → Media → Add New. Build a mapping table and save it:

   **`docs/research/ASSET_MAP.md`**
   ```
   | Original URL | Local file | WP Attachment ID | WP URL |
   ```
   You will need both the attachment ID and the WP URL for Elementor widget calls.

3. **Set global colors** — map the extracted palette to Elementor global colors:
   ```
   mcp__elementor__elementor-mcp-update-global-colors({
     colors: [
       { id: "primary",    title: "Primary",    value: "#xxxxxx" },
       { id: "secondary",  title: "Secondary",  value: "#xxxxxx" },
       { id: "accent",     title: "Accent",     value: "#xxxxxx" },
       { id: "text",       title: "Text",       value: "#xxxxxx" },
       { id: "background", title: "Background", value: "#xxxxxx" }
     ]
   })
   ```

4. **Set global typography** — map extracted fonts to Elementor global typography slots:
   ```
   mcp__elementor__elementor-mcp-update-global-typography({
     typography: [
       {
         id: "primary",
         title: "Primary Heading",
         value: {
           typography: "custom",
           font_family: "<extracted font family>",
           font_weight: "<weight>",
           font_size: { unit: "px", size: <size> },
           line_height: { unit: "em", size: <value> }
         }
       },
       {
         id: "secondary",
         title: "Body",
         value: {
           typography: "custom",
           font_family: "<extracted font family>",
           font_weight: "<weight>",
           font_size: { unit: "px", size: <size> }
         }
       }
     ]
   })
   ```

5. **Create the page:**
   ```
   mcp__elementor__elementor-mcp-create-page({
     title: "<site name> Clone",
     status: "publish",
     template: "elementor_canvas"
   })
   ```
   Record the returned `post_id` — every subsequent widget call needs it.

6. **(Optional) Set as WordPress front page** via WP-CLI:
   ```bash
   wp option update show_on_front page
   wp option update page_on_front <post_id>
   ```

7. **Load Elementor container schema** — do this once and note the key names:
   ```
   mcp__elementor__elementor-mcp-get-container-schema
   ```
   Critical keys to record: `flex_direction`, `flex_justify_content`, `flex_align_items`, `flex_gap`, `flex_wrap`, `content_width`, `boxed_width`, `min_height`, `padding`, `margin`, `background_background`, `background_color`, `background_image`.

---

## Phase 3: Component Specification & Build

### Step 1: Extract

*(Identical in both modes)*

For each section, use browser MCP to extract everything:

1. **Screenshot** the section in isolation (scroll to it, screenshot the viewport). Save to `docs/design-references/`.

2. **Extract CSS** for every element in the section using this script:

```javascript
(function(selector) {
  const el = document.querySelector(selector);
  if (!el) return JSON.stringify({ error: 'Element not found: ' + selector });
  const props = [
    'fontSize','fontWeight','fontFamily','lineHeight','letterSpacing','color',
    'textTransform','textDecoration','backgroundColor','background',
    'padding','paddingTop','paddingRight','paddingBottom','paddingLeft',
    'margin','marginTop','marginRight','marginBottom','marginLeft',
    'width','height','maxWidth','minWidth','maxHeight','minHeight',
    'display','flexDirection','justifyContent','alignItems','gap',
    'gridTemplateColumns','gridTemplateRows',
    'borderRadius','border','borderTop','borderBottom','borderLeft','borderRight',
    'boxShadow','overflow','overflowX','overflowY',
    'position','top','right','bottom','left','zIndex',
    'opacity','transform','transition','cursor',
    'objectFit','objectPosition','mixBlendMode','filter','backdropFilter',
    'whiteSpace','textOverflow','WebkitLineClamp'
  ];
  function extractStyles(element) {
    const cs = getComputedStyle(element);
    const styles = {};
    props.forEach(p => { const v = cs[p]; if (v && v !== 'none' && v !== 'normal' && v !== 'auto' && v !== '0px' && v !== 'rgba(0, 0, 0, 0)') styles[p] = v; });
    return styles;
  }
  function walk(element, depth) {
    if (depth > 4) return null;
    const children = [...element.children];
    return {
      tag: element.tagName.toLowerCase(),
      classes: element.className?.toString().split(' ').slice(0, 5).join(' '),
      text: element.childNodes.length === 1 && element.childNodes[0].nodeType === 3 ? element.textContent.trim().slice(0, 200) : null,
      styles: extractStyles(element),
      images: element.tagName === 'IMG' ? { src: element.src, alt: element.alt, naturalWidth: element.naturalWidth, naturalHeight: element.naturalHeight } : null,
      childCount: children.length,
      children: children.slice(0, 20).map(c => walk(c, depth + 1)).filter(Boolean)
    };
  }
  return JSON.stringify(walk(el, 0), null, 2);
})('SELECTOR');
```

3. **Extract multi-state styles** — for any element with multiple states (scroll-triggered, hover, active tab), capture BOTH states. Record the diff explicitly: "Property X changes from VALUE_A to VALUE_B, triggered by TRIGGER, with transition: TRANSITION_CSS."

4. **Extract real content** — all text, alt attributes, aria labels, placeholder text. For tabbed/stateful content, **click each tab and extract content per state**.

5. **Identify assets** this section uses. Check for **layered images** (multiple `<img>` or background-images stacked in the same container).

6. **Assess complexity** — how many distinct sub-components does this section contain?

---

### Step 2: Write the Component Spec File

For each section (or sub-component, if breaking it up), create a spec file in `docs/research/components/`. This is NOT optional in either mode.

**File path:** `docs/research/components/<component-name>.spec.md`

**Template:**

```markdown
# <ComponentName> Specification

## Overview
- **Target file (Next.js):** `src/components/<ComponentName>.tsx`
- **Target section (Elementor):** Section N of page post_id <id>
- **Screenshot:** `docs/design-references/<screenshot-name>.png`
- **Interaction model:** <static | click-driven | scroll-driven | time-driven>

## DOM Structure
<Describe the element hierarchy — what contains what>

## Computed Styles (exact values from getComputedStyle)

### Container
- display: ...
- padding: ...
- maxWidth: ...
- (every relevant property with exact values)

### <Child element 1>
- fontSize: ...
- color: ...
- (every relevant property)

## States & Behaviors

### <Behavior name>
- **Trigger:** <scroll position 50px | IntersectionObserver | click | hover>
- **State A (before):** maxWidth: 100vw, boxShadow: none
- **State B (after):** maxWidth: 1200px, boxShadow: 0 4px 20px rgba(0,0,0,0.1)
- **Transition:** transition: all 0.3s ease
- **Elementor approximation:** <closest Elementor equivalent, or "not achievable — document as known gap">

### Hover states
- **<Element>:** <property>: <before> → <after>, transition: <value>

## Per-State Content (if applicable)

### State: "Featured"
- Title: "..."
- Cards: [{ title, description, image, link }, ...]

## Assets
- Background image: original URL | WP attachment ID (Elementor) / `public/images/<file>.webp` (Next.js)
- Overlay image: original URL | WP attachment ID (Elementor) / `public/images/<file>.png` (Next.js)

## Text Content (verbatim)
<All text content, copy-pasted from the live site>

## Responsive Behavior
- **Desktop (1440px):** <layout description>
- **Tablet (768px):** <what changes>
- **Mobile (390px):** <what changes>
- **Breakpoint:** layout switches at ~<N>px

## Elementor Widget Plan
*(Fill this section only in Elementor mode — map every visual element to a widget)*
- Outer section container: add-container (flex_direction, padding, background...)
- Inner content container: add-container (content_width:"boxed", boxed_width:...)
- Main heading: add-heading (header_size, title_color, typography_*)
- Body copy: add-text-editor
- CTA: add-button
- Image: add-image (WP attachment ID: ...)
- Card grid: add-container (row, wrap) → duplicate first card N times
- Tabs: add-tabs
- Accordion: add-accordion
- Nav menu: uael-nav-menu widget
- Known gaps: <list behaviors that cannot be reproduced in Elementor>
```

Fill every section. If a section doesn't apply (e.g., no states for a static footer), write "N/A" — but think twice before marking States & Behaviors as N/A.

---

### Step 3A: Dispatch Builders (Next.js mode)

Based on complexity, dispatch builder agent(s) in worktree(s):

**Simple section** (1-2 sub-components): One builder agent gets the entire section.

**Complex section** (3+ distinct sub-components): Break it up. One agent per sub-component, plus one agent for the section wrapper. Sub-component builders go first since the wrapper depends on them.

**What every builder agent receives:**
- The full contents of its component spec file (inline in the prompt — don't say "go read the spec file")
- Path to the section screenshot in `docs/design-references/`
- Which shared components to import (`icons.tsx`, `cn()`, shadcn primitives)
- The target file path (e.g., `src/components/HeroSection.tsx`)
- Instruction to verify with `npx tsc --noEmit` before finishing
- For responsive behavior: the specific breakpoint values and what changes

**Don't wait.** As soon as you've dispatched the builder(s) for one section, move to extracting the next section. Builders work in parallel in their worktrees while you continue extraction.

#### Step 4A: Merge (Next.js mode)

As builder agents complete their work:
- Merge their worktree branches into main
- After each merge, verify the build still passes: `npm run build`
- If a merge introduces type errors, fix them immediately

The extract → spec → dispatch → merge cycle continues until all sections are built.

---

### Step 3B: Build in Elementor (Elementor mode)

Unlike Next.js mode, Elementor builds are **sequential** — all widget calls go to one WordPress site and cannot be parallelized. Work section-by-section, top to bottom, following the Page Topology order.

**For each section:**

1. Read the component spec, focusing on the "Elementor Widget Plan" section.
2. Load only the MCP tool schemas you need for this section via ToolSearch `select:` queries — don't load all 75 tools at once.
3. Build outer container → inner content container → widgets inside, in that order.
4. After each section completes, call `mcp__elementor__elementor-mcp-get-page-structure` and verify the nesting before moving on.
5. Record every `element_id` returned by widget creation calls — needed for cross-widget style overrides.

**Standard section structure:**
```
add-container (outer — full width, background, padding)
  └── add-container (inner — boxed, max-width ~1360px)
        ├── add-heading
        ├── add-text-editor
        ├── add-button
        └── add-image
```

**Card grids — use duplication, not HTML:**
```
1. Build the first card with native widgets (Container → Image → Heading → Text Editor → Button)
2. mcp__elementor__elementor-mcp-duplicate-element to copy it N times
3. mcp__elementor__elementor-mcp-update-element to change copy/image on each duplicate
4. Wrap all cards in a parent Container: flex_direction:"row", flex_wrap:"wrap"
```

**Cross-widget style overrides** — when widget controls don't expose a needed property, use a `<style>`-only HTML widget scoped to the element ID:
```html
<style>
.elementor-element-<id> .elementor-tab-title {
  text-transform: uppercase;
  letter-spacing: 0.2em;
}
</style>
```

**CSS → Elementor parameter translation:**

| Extracted CSS | Elementor parameter |
|---|---|
| `padding: 40px 80px` | `padding: {top:40, right:80, bottom:40, left:80, unit:"px", isLinked:false}` |
| `gap: 40px` | `flex_gap: {size:40, unit:"px"}` |
| `max-width: 1200px` | `content_width:"boxed", boxed_width:{size:1200, unit:"px"}` |
| `min-height: 100vh` | `min_height:{size:100, unit:"vh"}` |
| `background-color: #fff` | `background_background:"classic", background_color:"#ffffff"` |
| `background-image: url(...)` | `background_background:"classic", background_image:{url:"...", id:<wp_id>}` |
| `font-family: Inter` | `typography_typography:"custom", typography_font_family:"Inter"` |
| `font-size: 48px` | `typography_font_size:{size:48, unit:"px"}` |
| `font-weight: 700` | `typography_font_weight:"700"` |
| `line-height: 1.2` | `typography_line_height:{size:1.2, unit:"em"}` |
| `letter-spacing: 0.05em` | `typography_letter_spacing:{size:0.05, unit:"em"}` |
| `color: #333` (heading) | `title_color:"#333"` |
| `color: #333` (text editor) | `text_color:"#333"` |
| `border-radius: 8px` | `border_radius:{size:8, unit:"px"}` |
| `flex-direction: row` | `flex_direction:"row"` |
| `justify-content: center` | `flex_justify_content:"center"` |
| `align-items: center` | `flex_align_items:"center"` |
| `flex-wrap: wrap` | `flex_wrap:"wrap"` |
| background overlay opacity | `background_overlay_background:"classic", background_overlay_opacity:{unit:"px", size:0.5}` *(unit is always "px" even for opacity — Elementor quirk)* |

**Always set `typography_typography:"custom"`** before any other `typography_*` key, or they are silently ignored.

**Widget calls use flat params, NOT nested `settings:{}`** — except `add-container` which takes `settings:{}`. Don't generalize from one to the other:
```js
// CORRECT for add-heading, add-text-editor, add-button, add-image:
mcp__elementor__elementor-mcp-add-heading({
  post_id: 11, parent_id: "abc123",
  title: "Hello <em>World</em>",
  header_size: "h1",
  title_color: "#333",
  typography_typography: "custom",
  typography_font_family: "Inter",
  typography_font_size: {size: 64, unit: "px"}
})

// WRONG — silently fails:
mcp__elementor__elementor-mcp-add-heading({
  post_id: 11, parent_id: "abc123",
  settings: { title: "Hello", typography_font_family: "Inter" }
})
```

**Elementor behaviors that cannot be faithfully reproduced — document each as a known gap:**
- Scroll-driven animations (IntersectionObserver, parallax) → approximate with Elementor's built-in Entrance Animation
- Smooth scroll libraries (Lenis, Locomotive Scroll) → not available
- Scroll-snap → not available
- CSS `animation-timeline` → not available
- Elementor Pro features (Theme Builder, Loop Grid, Motion Effects, Popups) → require Pro license
- Sticky header behavior with style transition → note as gap; basic sticky available in free

Document every gap in `docs/research/ELEMENTOR_GAPS.md` as you encounter them.

---

## Phase 4: Page Assembly

### Next.js mode

After all sections are built and merged, wire everything together in `src/app/page.tsx`:

- Import all section components
- Implement the page-level layout from your topology doc (scroll containers, column structures, sticky positioning, z-index layering)
- Connect real content to component props
- Implement page-level behaviors: scroll snap, scroll-driven animations, dark-to-light transitions, intersection observers, smooth scroll (Lenis etc.)
- Verify: `npm run build` passes clean

### Elementor mode

After all sections are built on the page:

1. **Build the header** (if the original has one):
   - Tell the user to create the WordPress nav menu manually: WP Admin → Appearance → Menus → create "Main" menu. This cannot be done via MCP.
   - Create the header template:
     ```
     mcp__elementor__elementor-mcp-create-page({
       title: "Site Header",
       post_type: "elementor-hf",
       status: "publish"
     })
     ```
   - Set post meta via WP-CLI: `ehf_template_type = "type_header"`, `display-on-canvas = "yes"`
   - Build layout: logo + UAE Nav Menu widget (`uael-nav-menu`) pointed at "Main" menu + CTA button
   - Verify in WP Admin → Appearance → Header Footer Builder that display is "Entire Website"

2. **Build the footer** (if the original has one):
   - Same `post_type:"elementor-hf"`, `ehf_template_type = "type_footer"`
   - Typical: 4-column container (brand block + link columns) + bottom row for copyright/socials

3. **Final page structure check:**
   ```
   mcp__elementor__elementor-mcp-get-page-structure({post_id: <id>})
   ```
   Confirm all sections appear in the correct order with correct nesting.

4. **Write `docs/research/ELEMENTOR_GAPS.md`** — list every behavior from the original site that could not be reproduced, with a note on how the user could address it (e.g., "upgrade to Elementor Pro", "add custom CSS in WP Customizer", "use a third-party plugin").

---

## Phase 5: Visual QA Diff

### Next.js mode

1. Open the original site and your clone side-by-side at desktop (1440px), then mobile (390px)
2. Compare section by section, top to bottom
3. For each discrepancy: re-extract from browser MCP if the spec was wrong, or fix the component if the spec was right
4. Test all interactive behaviors: scroll, click every button/tab, hover over interactive elements
5. Verify smooth scroll, header transitions, tab switching, animations

### Elementor mode

1. Open the original site and the WordPress preview side-by-side at desktop (1440px)
2. For each visual discrepancy:
   - Is it an Elementor limitation? → Add to `ELEMENTOR_GAPS.md`
   - Is it a wrong parameter? → `mcp__elementor__elementor-mcp-update-element` with corrected value
   - Is it a missing widget? → Add it with correct params
3. Check mobile (390px) via browser MCP or WP's mobile preview
4. Test all click-driven interactions (tabs, accordions, buttons)
5. Review `ELEMENTOR_GAPS.md` with the user so they understand what's missing and why

Only after this visual QA pass is the clone complete.

---

## Pre-Dispatch / Pre-Build Checklist

Before dispatching ANY builder agent (Next.js) or starting widget calls for a section (Elementor), verify every box:

- [ ] Spec file written to `docs/research/components/<name>.spec.md` with ALL sections filled
- [ ] Every CSS value in the spec is from `getComputedStyle()`, not estimated
- [ ] Interaction model is identified and documented (static / click / scroll / time)
- [ ] For stateful components: every state's content and styles are captured
- [ ] For scroll-driven components: trigger threshold, before/after styles, and transition are recorded
- [ ] For hover states: before/after values and transition timing are recorded
- [ ] All images in the section are identified (including overlays and layered compositions)
- [ ] Responsive behavior is documented for at least desktop and mobile
- [ ] Text content is verbatim from the site, not paraphrased
- [ ] *(Next.js)* Builder prompt is under ~150 lines of spec; if over, split the section
- [ ] *(Elementor)* "Elementor Widget Plan" section of the spec is filled — every element mapped to a widget

---

## What NOT to Do

- **Don't build click-based tabs when the original is scroll-driven (or vice versa).** Determine the interaction model FIRST by scrolling before clicking. This is the #1 most expensive mistake.
- **Don't extract only the default state.** Click every tab/pill and capture all states.
- **Don't miss overlay/layered images.** Check every container's DOM tree for multiple `<img>` elements and positioned overlays.
- **Don't build mockup components for content that's actually videos/animations.**
- **Don't approximate CSS values.** Extract exact `getComputedStyle()` values.
- **Don't skip asset extraction.** Without real images, videos, and fonts, the clone will always look fake.
- **Don't skip responsive extraction.** Test at 1440, 768, and 390 during extraction.
- **Don't dispatch builders without a spec file.**

### Next.js only

- **Don't reference docs from builder prompts.** Each builder gets the CSS spec inline.
- **Don't build everything in one monolithic commit.**
- **Don't bundle unrelated sections into one agent.**
- **Don't forget smooth scroll libraries** (Lenis, Locomotive Scroll).

### Elementor only

- **Don't paste a whole section as a single HTML widget.** The user cannot edit it in Elementor. Break every section into native widgets.
- **Don't nest `settings:{}` in `add-heading`, `add-text-editor`, `add-button`, `add-image` calls.** Only `add-container` takes `settings:{}`.
- **Don't forget `typography_typography:"custom"`.** Without this flag, all other typography_* keys are silently ignored.
- **Don't try to reproduce scroll-driven animations exactly.** Use Elementor's Entrance Animation as approximation and document the gap.
- **Don't build a header/footer without the HFE or UAE plugin installed.**
- **Don't skip `ELEMENTOR_GAPS.md`.** The user needs to know what the clone can and cannot do before handover.

---

## Completion Report

When done, report:

### Both modes
- Total sections built
- Total spec files written (should match sections)
- Total assets downloaded/uploaded

### Next.js mode
- Total React components created
- Build status (`npm run build` result)
- Visual QA results (any remaining discrepancies)
- Any known gaps or limitations

### Elementor mode
- WordPress page URL
- List of native Elementor widgets used (counts by type)
- Summary of `docs/research/ELEMENTOR_GAPS.md`
- Any sections that required HTML widget fallback and the specific reason why
