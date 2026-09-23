import { defineConfig } from '@playwright/test';

// Target the container-served page per contracts/tracer-bullet-deployment.md.
// Override with PLAYWRIGHT_BASE_URL (e.g. http://localhost:4173/csp/sentai/ for `npm run preview`).
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:52773/csp/sentai/';

export default defineConfig({
	testDir: 'tests',
	use: {
		baseURL,
		trace: 'retain-on-failure'
	},
	reporter: 'list'
});
