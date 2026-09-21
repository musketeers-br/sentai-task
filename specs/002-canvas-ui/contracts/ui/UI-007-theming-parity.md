# UI-007 · Theming parity

**Image**: [`../screens/FlowLight.png`](../screens/FlowLight.png) · **Viewport** 1440×900 · **Theme** light
**Route**: `/flows/[id]` with `data-theme="light"` · **Covers**: FR-037, Constitution VI

The same screen as [UI-001](./UI-001-flow-canvas.md), in the light theme. It exists to
make one claim checkable: **the light theme was designed, not derived.**

---

## What is identical to UI-001

Everything structural. Same four regions at the same sizes, same graph, same node
anatomy, same handle geometry, same fan-in treatment, same inspector sections in the same
order, same status bar, same strings. If the two screens differ in anything other than
colour and the two items below, one of them is a defect.

## What differs, and why

### 1. Elevation inverts

In dark, the node card (`#141A26`) is **lighter** than the ground (`#0A0D13`) — it rises
out of it. In light, the node card (`#FFFFFF`) is **lighter** than the warm paper ground
(`#EFEDE7`) too, but the canvas itself flips to pure white while the rails stay on paper.
So in dark the canvas is the darkest surface and in light it is the lightest.

This is the concrete reason an inversion cannot work: `invert(dark)` would give a light
theme whose canvas is the *darkest* surface, with the rails floating above it. That reads
as a hole in the page.

### 2. Selection is a shadow, not a glow

Dark marks the selected node with a 3 px translucent halo — light bleeding outward, which
only reads against a dark ground. Light marks it with a 2 px solid accent border plus a
tighter wash, and nodes carry a 1 px `rgba(22,24,29,0.07)` drop shadow that the dark theme
does not have at all.

Glow is a dark-theme device; shadow is a light-theme device. Neither is a computed
version of the other.

### 3. The state and category hues are different values, not different lightnesses

| Role | Dark | Light |
|---|---|---|
| category / verification | `#FF3B4A` | `#D91F2E` |
| category / storage | `#3B8DFF` | `#1F6FD6` |
| category / journal | `#FFC93B` | `#C68A00` |
| category / purge | `#35D07F` | `#1F8E52` |
| category / custom | `#9AA7BC` | `#7A8296` |
| destructive | `#FF3B4A` | `#C0212F` |
| warning | `#FFC93B` | `#9A6A00` |

The light values are not the dark ones darkened by a constant. Each was picked to hold
≥4.5:1 against white where it carries text, and to stay distinguishable from its
neighbours at an 8 px swatch. Yellow moves furthest, because a yellow that reads as
warning on ink is invisible on paper.

### 4. Edge tokens

Dark: sequence `#5E6E85`, join `#C6D2E2` — the join is *lighter* than the ground.
Light: sequence `#8A93A3`, join `#16181D` — the join is *darker* than the ground.

The join edge is the one that must dominate, so in each theme it moves away from the
ground in the direction that has contrast available.

## Theme switch

The `Dark` / `Light` control sits in the top bar of every screen, and the choice
persists per viewer. The switch sets `data-theme` on `:root`; no component reads the
theme in script to pick a colour.

## How this is tested

The visual test for this screen is a **differential** test, not a standalone one:

1. Render `/flows/[id]` in both themes at 1440×900.
2. Assert the structural assertions of UI-001 pass in both.
3. Assert every contract string is present in both.
4. Assert contrast ≥4.5:1 in both.
5. Assert that **no token's light value equals the inverse of its dark value** — a
   mechanical guard against someone reintroducing `filter: invert` or a computed ramp
   during a refactor.

Step 5 is the one that gives this contract teeth. Without it, a future refactor can
satisfy every other assertion with a derived theme.

## Not bound

Which theme a given viewer sees first, beyond the product default of dark. Whether the
switch follows `prefers-color-scheme` on first visit.
