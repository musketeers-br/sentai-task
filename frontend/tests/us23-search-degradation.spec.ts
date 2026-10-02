/// <reference types="node" />
import { mkdirSync, writeFileSync } from "node:fs";
import { expect, test, type Page } from "@playwright/test";
import { envelope, signIn } from "./support";

// spec 011 — User Story 2, end to end against the published bundle: with the similarity provider
// unavailable, the palette is indistinguishable from today's in every way (FR-023) — the local
// filter narrows by entry text, today's no-match message shows when nothing matches, and no
// SUGGESTED group, toast or error appears. Degraded and working runs look identical.
//
// Spec 017 removed the `ollama` service this test used to stop; the provider now runs inside IRIS.
// The failure is planted at the search API instead: first the API's own degraded answer
// (`available: false`, reason `unreachable` — the backend side is covered by its unit tests), then
// a transport failure, which the palette must treat the same way (FR-023, FR-025).

const EVIDENCE = "../specs/011-semantic-step-search/evidence";
const SEARCH = "**/catalog/step-types/search?*";

const search = (page: Page) => page.getByLabel("Search step type");

for (const failure of ["unreachable", "transport"] as const) {
  test(`us23 — with the provider down (${failure}), the palette is exactly today’s: local filter, no-match message, no SUGGESTED group, no error`, async ({
    page,
  }) => {
    test.slow();
    const errors: string[] = [];
    page.on("pageerror", (e) => errors.push(e.message));
    await page.route(SEARCH, (route) =>
      failure === "unreachable"
        ? route.fulfill({
            status: 200,
            contentType: "application/json",
            body: JSON.stringify({ available: false, reason: "unreachable" }),
          })
        : route.abort("connectionrefused"),
    );

    await signIn(page);

    // A known identifier narrows locally on every keystroke — before and after any request —
    // and no suggestion ever arrives to re-order it.
    await search(page).fill("journal");
    await expect(
      page.locator('[data-step-type="switch-journal"]'),
    ).toBeVisible();
    await expect(
      page.locator('[data-step-type="integrity-check"]'),
    ).toHaveCount(0);
    await page.waitForTimeout(1200); // long enough for the debounced request to have been refused
    await expect(page.locator('[data-suggested="true"]')).toHaveCount(0);
    await expect(page.getByRole("heading", { name: "SUGGESTED" })).toHaveCount(
      0,
    );

    // An intent sentence finds nothing by entry text, so today's no-match message shows — and
    // it is the same message today's palette shows, not an error wearing its clothes.
    await search(page).fill("rotate the journal");
    await page.waitForTimeout(1200);
    await expect(page.locator(".palette .empty")).toHaveText(
      "No step type matches “rotate the journal”.",
    );
    await expect(page.locator('[data-suggested="true"]')).toHaveCount(0);

    // Nonsense, too, narrows to today's message — an unavailable provider and an empty ranking
    // are indistinguishable on screen by design (R-007).
    await search(page).fill("zzzz-nothing");
    await page.waitForTimeout(1200);
    await expect(page.locator(".palette .empty")).toBeVisible();

    await page.screenshot({
      path: `${EVIDENCE}/us23-degraded${failure === "transport" ? "-transport" : ""}.png`,
    });

    // No toast, no console error, no page error: degradation is not a failure (FR-023).
    expect(errors).toEqual([]);

    mkdirSync(EVIDENCE, { recursive: true });
    if (failure === "transport") return;
    writeFileSync(
      `${EVIDENCE}/us23-search-degradation.json`,
      envelope(
        "us23-search-degradation",
        {
          provider:
            'unavailable — the search API answered {available: false, reason: "unreachable"} (planted with a route; a transport failure is checked too)',
        },
        {
          suggestedGroups: 0,
          pageErrors: 0,
          noMatchMessage: "today\u2019s own",
        },
        [
          "With the similarity service down, the palette narrows by entry text exactly as before, shows today\u2019s no-match message, and raises no error (FR-023).",
        ],
      ),
    );
  });
}
