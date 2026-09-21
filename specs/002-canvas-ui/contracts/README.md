# Contracts

This directory holds everything downstream work is checked against. Three kinds:

| Kind | Files | Binds |
|---|---|---|
| **Screen contracts** | `screens/*.png` + `ui/UI-00*.md` | What the operator sees and can do |
| **API contract** | `openapi.yaml` | The REST surface between front end and IRIS |
| **Data contracts** | `flow-definition.schema.json`, `tokens.json` | Serialised flow, design tokens |

---

## Why the PNGs are contracts and not mockups

A mockup is a suggestion: the implementer looks at it, forms an impression, and writes
something in the neighbourhood. A contract is checkable: a reviewer can hold the built
screen next to the image and point at a difference, and a test can fail.

These seven images were rendered from the design source at 2× device pixel ratio, at the
exact viewport each screen is specified for. Nothing in them is placeholder: every task
name, namespace, database directory, GUID, duration and error string is the real
vocabulary the product will show. There is no lorem ipsum, and there are no invented
metrics *(Constitution VIII)*.

So when `plan.md` says the screens are binding, it means: **an implementation that
disagrees with one of these images is wrong until the image is amended.**

## What a screen contract binds

For each screen, its `ui/UI-00*.md` file lists three things explicitly:

1. **Structure** — which regions exist, their order, and what is fixed versus scrollable.
   A sidebar that becomes a top bar is a contract change.
2. **States and their encoding** — which states appear, and the shape that carries each
   one. Shape is the contract; colour is a token *(Constitution II)*.
3. **Vocabulary** — the exact strings for labels, column headers, states and warnings.
   These are IRIS terms and are not paraphrasable *(Constitution IV)*.

## What it does not bind

- **Exact pixel values.** Paddings, radii and font sizes come from `tokens.json`. The
  image shows a correct rendering of those tokens, not an independent source for them.
- **Copy the spec does not pin.** Body text inside an explanation panel may be reworded
  as long as it says the same thing. Labels, headers and state names may not.
- **The sample data.** `Heavy maintenance — Saturday 03:00`, the GUID `3F9C21A0-…`, the
  durations — these are a worked example chosen to exercise every state. The
  implementation reads real data.
- **Breakpoint behaviour below the contract viewport.** Out of scope for v1; the product
  targets a desktop operations console.

## How they are tested

`frontend/tests/visual/` drives each route to the contract viewport at
`deviceScaleFactor: 2` and asserts, in this order:

1. The named regions exist with the specified ordering — structural, not pixel.
2. Every state listed in the contract renders its specified shape, asserted on the SVG
   path, not on colour.
3. Every contract string is present verbatim.
4. Contrast: every text node ≥4.5:1 against its computed background (≥3:1 at ≥24 px), in
   **both** themes.
5. A pixel diff against the reference PNG at 0.3 % tolerance — a change detector, not a
   gate. A diff that trips sends a human to look; it does not by itself fail the build.

Rationale for 5 being advisory is in `research.md` R-008.

## The screens

| ID | Screen | Image | Viewport | Theme | Primary requirements |
|---|---|---|---|---|---|
| UI-001 | Flow Canvas | `screens/Main.png` | 1440×900 | dark | FR-001…011 |
| UI-002 | Live run | `screens/LiveRun.png` | 1440×900 | dark | FR-018…027 |
| UI-003 | Task catalog | `screens/Catalog.png` | 1440×900 | light | FR-028…031 |
| UI-004 | Run history | `screens/RunTimeline.png` | 1440×640 | dark | FR-032…036 |
| UI-005 | WQM category | `screens/WQM.png` | 1100×1000 | light | FR-015…017 |
| UI-006 | Design system | `screens/System.png` | 1100×880 | both | FR-020, FR-037, FR-038 |
| UI-007 | Theming parity | `screens/FlowLight.png` | 1440×900 | light | FR-037 |

UI-006 is the normative one for state shapes and theme tokens. Where another screen and
UI-006 disagree about a shape or a token, UI-006 wins and the other screen is the defect.

## Amending a contract

1. Change the design source, re-render the PNG at the same viewport and scale.
2. Update the affected `ui/UI-00*.md` — structure, states or vocabulary.
3. Update the visual test's assertions in the same commit.
4. If the change touches a constitutional principle, amend the constitution first and
   bump its version.

A regenerated baseline with no matching change to the `.md` is not an amendment; it is
the contract quietly disappearing.
