import { expect, test } from '@playwright/test';

// The canvas page is public: no browser prompt, the operator signs in once inside the canvas.
// What stays protected is the API — nothing about flows or runs is reachable without a token,
// and its 401 carries no Basic challenge, so the browser never pops a prompt for it.
test('the canvas page is public and the API is not', async ({ baseURL }) => {
	for (const path of ['', 'index.html', '_app/version.json']) {
		const res = await fetch(new URL(path, baseURL));
		expect(res.status, path).toBe(200);
		expect(res.headers.get('www-authenticate'), path).toBeNull();
	}

	// Nothing outside the build root, however the path is spelled.
	const escape = await fetch(new URL('..%2F..%2Fetc%2Fpasswd', baseURL));
	expect(escape.status).toBe(404);

	const api = await fetch(new URL('api/v1/flows', baseURL));
	expect(api.status).toBe(401);
	expect(api.headers.get('www-authenticate')).toBeNull();
});
