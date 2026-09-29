#!/usr/bin/env node
// Spec 014: `node --use-system-ca scripts/media/check-articles.mjs <article.md>… [--offline]`
// Exits 1 when any article has a problem. --offline skips the link requests. --use-system-ca lets
// Node verify sites whose certificate chain only the operating system completes (the Ideas portal).
import { readFileSync } from 'node:fs';
import { brokenLinks, staticProblems, wordCount, frontMatter } from './articles.mjs';

const args = process.argv.slice(2);
const offline = args.includes('--offline');
const files = args.filter((a) => !a.startsWith('--'));
if (files.length === 0) {
	console.error('usage: node scripts/media/check-articles.mjs <article.md>… [--offline]');
	process.exit(64);
}

let failed = false;
for (const file of files) {
	const text = readFileSync(file, 'utf8');
	const problems = staticProblems(text);
	if (!offline) for (const link of await brokenLinks(text)) problems.push(`broken link: ${link}`);
	const fm = frontMatter(text) ?? {};
	console.log(`${problems.length ? 'FAIL' : 'PASS'} ${file} (${fm.lang ?? '?'}, ${fm.status ?? '?'}, ${wordCount(text)} words)`);
	for (const p of problems) console.log(`  - ${p}`);
	failed ||= problems.length > 0;
}
process.exit(failed ? 1 : 0);
