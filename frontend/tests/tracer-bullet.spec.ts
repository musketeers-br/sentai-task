import { expect, test } from '@playwright/test';

// Verifies contracts/tracer-bullet-deployment.md items 3-6 against the served page.
test('tracer bullet renders 3 nodes and 1 sequence edge, with no backend calls', async ({
	page
}) => {
	const requests: string[] = [];
	page.on('request', (req) => requests.push(req.url()));

	// IRIS's "Serve files" CSP application does not resolve a bare directory path to
	// `index.html` (verified empirically — see tracer-bullet-deployment.md "Deviation").
	// The dev-preview server (adapter-static's own server) does resolve `/`, so both
	// targets need the explicit filename here.
	const response = await page.goto('index.html');
	expect(response?.status()).toBe(200);

	const nodes = page.locator('.svelte-flow__node');
	await expect(nodes).toHaveCount(3);

	const edges = page.locator('.svelte-flow__edge');
	await expect(edges).toHaveCount(1);

	// Sequence edge treatment (UI-006): 1.5px stroke, arrowhead — never the 2.5px join treatment.
	const edgePath = page.locator('.svelte-flow__edge-path').first();
	const strokeWidth = await edgePath.evaluate((el) => getComputedStyle(el).strokeWidth);
	expect(strokeWidth).toBe('1.5px');
	await expect(edgePath).toHaveAttribute('marker-end', /arrowclosed/);

	const forbidden = requests.filter(
		(url) => url.includes('/api/admin') || url.includes('/csp/sentai/api/v1')
	);
	expect(forbidden).toEqual([]);
});
