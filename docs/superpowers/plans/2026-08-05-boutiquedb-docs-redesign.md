# BoutiqueDB Documentation Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current Maple-based docs-first presentation with a polished Aspen-based product landing page and a clearly separated, highly usable documentation experience in both light and dark mode.

**Architecture:** Keep `/` as a hidden, `mode: custom` marketing landing page with only the product navbar visible. Route all onboarding CTAs into `/getting-started/quick-start`, where the full documentation sidebar begins. Use Aspen for the documentation shell and implement the BoutiqueDB visual system in `styles.css` so the custom landing and native Mintlify components share the same color, radius, depth, and interaction language.

**Tech Stack:** Mintlify `docs.json`, MDX, custom CSS, Font Awesome icons, existing BoutiqueDB PNG assets, GitHub PR workflow.

## Global Constraints

- English-only for this iteration; translation architecture remains deferred.
- Do not add a new JavaScript framework, runtime dependency, or external asset CDN.
- Preserve all existing documentation URLs.
- Preserve the BoutiqueDB icon and GitHub/Swift Package Index destinations.
- The landing page must not show the documentation sidebar or table of contents.
- Documentation pages must retain searchable, navigable sidebar behavior.
- Light mode must be intentionally designed, not a simple inversion of dark mode.
- Cards must be compact, square-leaning, centered, and semantically colored.
- Open a PR only after MDX/config validation, navigation inspection, responsive CSS review, and final diff review are complete.

---

## Theme decision

### Evaluated rendered implementations

- **Maple — current BoutiqueDB site:** attractive centered hero in dark mode, but the shell produces broad rounded surfaces, oversized horizontal cards, large unused bands, and a weak light-mode identity.
- **Almond — ComfyUI docs:** excellent information discovery and card-catalog density, but its visual hierarchy is portal-like and utility-heavy. It would compete with BoutiqueDB's custom feature-card system rather than supporting it.
- **Aspen — CrewAI docs:** supports a product-oriented landing page, dense multi-level navigation, custom components, and a stronger separation between overview content and documentation. Its shell is structured without imposing a card-first homepage.
- **Luma — Mintlify's Luma demo:** clear and readable, but intentionally airy and visually lightweight; it does not provide enough depth or product presence for BoutiqueDB.
- **Mint, Willow, Palm, Linden, Sequoia:** rejected respectively for conventional docs styling, excessive minimalism, enterprise/fintech character, terminal gimmickry, or content-library emphasis over product presentation.

**Selected theme: `aspen`.** It gives the best documentation shell for BoutiqueDB while leaving the custom landing page and card system under our control.

---

## File structure

- Modify `docs/docs.json`: switch to Aspen, refine global colors/background/navbar/footer/search, and keep the documentation shell product-oriented.
- Modify `docs/index.md`: replace the current docs overview with the complete custom landing page.
- Modify `docs/styles.css`: define the full light/dark token system, landing layout, cards, architecture visual, code surface, shadows, native Mintlify component polish, navbar/sidebar states, and responsive behavior.
- Modify navigation metadata through Mintlify Admin MCP: hide `/` from the sidebar, rename/reorder tabs and groups, and polish raw sidebar titles.
- Create `docs/superpowers/plans/2026-08-05-boutiquedb-docs-redesign.md`: retain this implementation record.

---

### Task 1: Migrate the documentation shell to Aspen

**Files:**
- Modify: `docs/docs.json`

**Produces:** Aspen theme shell, warm technical light mode, deep navy dark mode, grid decoration, product navbar, and consistent code block styling.

- [ ] Set `theme` to `aspen`.
- [ ] Set brand colors to coral primary (`#F25F3A`), lighter coral dark-mode accent (`#FF9B7A`), and deep rust interaction color (`#C9432B`).
- [ ] Set background decoration to `grid` with light `#F7F6F2` and dark `#07101E`.
- [ ] Keep system appearance switching enabled.
- [ ] Set navbar links to GitHub and Swift Package Index, with `Get Started` as the primary action.
- [ ] Use breadcrumb eyebrows on docs pages and keep separate light/dark Shiki themes.
- [ ] Update footer copy destinations so the product, documentation, and contributor paths are coherent.
- [ ] Validate the config through Mintlify's schema-backed `update_config` call.

### Task 2: Separate the landing page from the docs experience

**Files:**
- Modify: `docs/index.md`
- Modify navigation metadata through Mintlify MCP

**Produces:** `/` behaves as a product page; documentation chrome appears only after entering a docs route.

- [ ] Keep `index` in `mode: custom`, hidden from sidebar navigation, indexed for search engines, and without footer pagination.
- [ ] Rename the top tabs to `Docs` and `Architecture`.
- [ ] Point the Docs tab at `/getting-started/quick-start` and Architecture at `/advanced/boutiquedb-architecture`.
- [ ] Move `Getting Started` before conceptual/reference groups.
- [ ] Rename the old Overview group to `Fundamentals`.
- [ ] Polish sidebar labels for `stack`, `sync-overview`, and `open-options`.
- [ ] Confirm that all existing paths remain unchanged.

### Task 3: Build the product landing page

**Files:**
- Modify: `docs/index.md`

**Produces:** complete product page with clear hierarchy and conversion path.

- [ ] Build a split hero with product copy on the left and a layered BoutiqueDB engine visual on the right.
- [ ] Add the platform/status strip: Swift 6, iOS, macOS, SQLite-compatible, local-first.
- [ ] Add primary `Get Started` and secondary `Explore Architecture` actions.
- [ ] Add a centered 2x2 feature grid with distinct coral, blue, violet, and teal semantic treatments.
- [ ] Add a visual architecture section showing SwiftUI → LiveQuery → BoutiqueDB Actor → Turso/CloudKit.
- [ ] Add a Swift code window demonstrating `@Table` and `@LiveQuery`.
- [ ] Add three compact product-principle cards and a final conversion CTA.
- [ ] Keep copy technically accurate and avoid unsupported performance claims.
- [ ] Validate the complete MDX through Mintlify `write_page`.

### Task 4: Implement the full visual system manually

**Files:**
- Modify: `docs/styles.css`

**Produces:** intentionally designed light/dark modes, depth, responsive behavior, and shared component styling.

- [ ] Define semantic CSS variables for backgrounds, surfaces, text, borders, coral, blue, violet, teal, and shadows in light mode.
- [ ] Override the variables in `.dark` with independently tuned dark-mode values.
- [ ] Style the landing container, split hero, subtle grid/noise layers, glow effects, logo pedestal, engine stack, and floating capability chips.
- [ ] Implement compact feature cards with minimum height, balanced aspect, colored icon wells, top accent lines, layered shadows, and restrained hover lift.
- [ ] Implement architecture, code, principle, and CTA surfaces with progressive depth rather than identical borders.
- [ ] Polish native Mintlify cards, steps, code blocks, callouts, tables, selected sidebar links, navbar, search, and tabs so they match the new system.
- [ ] Ensure focus-visible states remain obvious and motion respects `prefers-reduced-motion`.
- [ ] Add breakpoints for large desktop, tablet, and mobile; collapse hero/architecture/code grids and make CTA buttons full-width where needed.

### Task 5: Validation and iteration gate

**Files:**
- Inspect: `docs/docs.json`, `docs/index.md`, `docs/styles.css`, navigation tree

**Produces:** verified branch ready for review, with no premature PR.

- [ ] Read back `index`, `styles.css`, and `docs.json` from the active Mintlify session.
- [ ] Inspect the complete Mintlify diff and confirm only intentional files/navigation metadata changed.
- [ ] Confirm every landing link points to an existing page.
- [ ] Confirm `/` is hidden from sidebar but remains the logo destination.
- [ ] Confirm Docs and Architecture tabs resolve to their intended entry pages.
- [ ] Review CSS at desktop, tablet, and mobile breakpoints for overflow, oversized cards, unreadable contrast, and missing stacking rules.
- [ ] Save to the branch with `mode: commit`, not PR.
- [ ] Compare branch against `main` through GitHub and verify the final file list and diff size.
- [ ] Check available commit/CI status and report any absent automated checks honestly.
- [ ] Open a non-draft PR only after all previous steps pass.

### Task 6: PR evidence

**Produces:** reviewable pull request that states exactly what changed and what was validated.

- [ ] Use a PR title focused on the completed redesign rather than partial polish.
- [ ] Include theme rationale, landing/docs split, card system, light/dark treatment, navigation changes, responsive coverage, and validation evidence in the PR body.
- [ ] Explicitly state that translation was intentionally deferred.
- [ ] Do not claim screenshot or browser validation unless actual visual evidence was obtained.
