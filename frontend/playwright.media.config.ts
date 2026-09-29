/// <reference types="node" />
// Spec 014: the media recorder (not part of the e2e suite, which uses playwright.config.ts and
// never looks in media/). `npx playwright test -c playwright.media.config.ts`
import { defineConfig } from '@playwright/test';

export default defineConfig({
	testDir: 'media',
	workers: 1,
	timeout: 300_000,
	outputDir: process.env.SENTAI_MEDIA_OUT ?? 'media-results',
	use: {
		baseURL: process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:52773/csp/sentai/',
		viewport: { width: 1280, height: 720 },
		deviceScaleFactor: 1,
		launchOptions: { slowMo: 150 },
		video: { mode: 'on', size: { width: 1280, height: 720 } }
	},
	reporter: 'list'
});
