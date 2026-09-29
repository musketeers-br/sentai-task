// Spec 014 T006: `node --test scripts/media/` (Node's own runner; no dependency).
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { test } from 'node:test';
import { brokenLinks, frontMatter, REQUIRED_SECTIONS, staticProblems, wordCount } from './articles.mjs';

const words = (n) => Array.from({ length: n }, (_, i) => `word${i}`).join(' ');

function article({ lang = 'en', status = 'draft', body = words(1000), extra = '', sections = REQUIRED_SECTIONS[lang] } = {}) {
	return [
		`<!-- lang: ${lang} | target: community | status: ${status} | published: -->`,
		'# Title',
		...sections.map((s) => `## ${s}\n`),
		body,
		extra
	].join('\n');
}

test('a complete draft has no static problem', () => {
	assert.deepEqual(staticProblems(article()), []);
});

test('front matter is read', () => {
	assert.equal(frontMatter(article({ status: 'ready' })).status, 'ready');
	assert.match(staticProblems('# no front matter\n' + words(1000)).join('|'), /front matter missing/);
});

test('too short and too long', () => {
	assert.match(staticProblems(article({ body: words(100) })).join('|'), /words \(expected 900–1600\)/);
	assert.match(staticProblems(article({ body: words(2000) })).join('|'), /words/);
});

test('code blocks and link targets do not count as words', () => {
	const text = article({ body: words(950) + '\n```\n' + words(2000) + '\n```\n[x](https://example.org/a/b/c)' });
	assert.ok(wordCount(text) < 1000);
});

test('a missing section is named', () => {
	const sections = REQUIRED_SECTIONS.en.slice(1);
	assert.match(staticProblems(article({ sections })).join('|'), /section missing: ## How a flow runs/);
});

test('relative links are refused; anchors are fine', () => {
	assert.match(staticProblems(article({ extra: '[readme](README.md)' })).join('|'), /relative link/);
	assert.deepEqual(staticProblems(article({ extra: '[top](#title)' })), []);
});

test('credentials, private addresses and e-mail are refused', () => {
	assert.match(staticProblems(article({ extra: 'password: hunter2' })).join('|'), /credential in the text/);
	assert.match(staticProblems(article({ extra: 'sign in as _SYSTEM / SYS' })).join('|'), /default administrator/);
	assert.match(staticProblems(article({ extra: 'at 192.168.1.20' })).join('|'), /private IPv4/);
	assert.match(staticProblems(article({ extra: 'write to a@b.com' })).join('|'), /e-mail/);
});

test('ready refuses leftover "after" markers', () => {
	assert.deepEqual(staticProblems(article({ status: 'draft', extra: '<!-- after 013 merge -->' })), []);
	assert.match(staticProblems(article({ status: 'ready', extra: '<!-- after 013 merge -->' })).join('|'), /markers remain/);
});

test('the Portuguese article has its own sections', () => {
	assert.deepEqual(staticProblems(article({ lang: 'pt-br' })), []);
});

test('broken links are found through a local stub', async () => {
	const server = createServer((req, res) => {
		res.statusCode = req.url === '/ok' ? 200 : req.url === '/moved' ? 301 : 404;
		if (res.statusCode === 301) res.setHeader('Location', '/ok');
		res.end();
	});
	await new Promise((r) => server.listen(0, r));
	const base = `http://127.0.0.1:${server.address().port}`;
	try {
		const text = article({ extra: `[a](${base}/ok) [b](${base}/moved) [c](${base}/missing)` });
		assert.deepEqual(await brokenLinks(text), [`${base}/missing`]);
	} finally {
		server.close();
	}
});
