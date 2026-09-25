import { defineConfig } from '@playwright/test';

// Targets the container-served app by default (the deployed artifact). For quick iteration
// against `npm run dev`, set PLAYWRIGHT_BASE_URL=http://localhost:5173/csp/sentai/ APP_ENTRY=''.
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:52773/csp/sentai/';

export default defineConfig({
	testDir: 'tests',
	// Tests share one IRIS instance; run them one at a time.
	workers: 1,
	use: {
		baseURL,
		// The /csp/sentai app is password-protected: IRIS answers 401 + WWW-Authenticate: Basic,
		// which a person answers in the browser's sign-in prompt and the tests answer here.
		httpCredentials: {
			username: process.env.IRIS_USER ?? '_SYSTEM',
			password: process.env.IRIS_PASSWORD ?? 'SYS'
		},
		// Evidence contract (spec.md): canvas captures at 1440×900, deviceScaleFactor 2.
		viewport: { width: 1440, height: 900 },
		deviceScaleFactor: 2,
		trace: 'retain-on-failure'
	},
	reporter: 'list'
});
