// One-off evidence capture for contracts/tracer-bullet-deployment.md.
// Run: node scripts/capture-tracer-evidence.mjs
import { chromium } from '@playwright/test';
import { mkdirSync, writeFileSync } from 'node:fs';

const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? 'http://localhost:52773/csp/sentai/';
const outDir = '../specs/002-canvas-ui/evidence';
mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: 1024, height: 640 } });

const requests = [];
page.on('request', (req) => requests.push({ url: req.url(), method: req.method() }));

await page.goto(new URL('index.html', baseURL).toString());
await page.waitForSelector('.svelte-flow__node');

await page.screenshot({ path: `${outDir}/tracer-render.png` });

const forbidden = requests.filter(
	(r) => r.url.includes('/api/admin') || r.url.includes('/csp/sentai/api/v1')
);
writeFileSync(
	`${outDir}/tracer-network.json`,
	JSON.stringify({ captured_at: new Date().toISOString(), baseURL, requests, forbidden }, null, 2)
);

await browser.close();
console.log('Evidence written to', outDir);
