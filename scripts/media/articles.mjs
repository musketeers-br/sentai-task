// Spec 014 (plan D-6): checks a community article before it is published. Pure functions over the
// article text, plus a link checker that takes an injected fetch (tests use a local stub).
//
// Front matter, first line of the file (not published):
//   <!-- lang: en | target: community.intersystems.com | status: draft|ready | published: <url> -->

export const REQUIRED_SECTIONS = {
	en: ['How a flow runs', 'The six areas', 'Distributed work (DPI-I-588)', 'Security by delegation', 'How it was built', 'Try it'],
	'pt-br': ['Como um flow executa', 'As seis áreas', 'Trabalho distribuído (DPI-I-588)', 'Segurança por delegação', 'Como foi construído', 'Experimente']
};

export const WORDS = { min: 900, max: 1600 };

const FORBIDDEN = [
	{ name: 'private IPv4 address', re: /\b(10\.\d{1,3}|192\.168|172\.(1[6-9]|2\d|3[01]))\.\d{1,3}\.\d{1,3}\b/ },
	{ name: 'credential in the text', re: /\b(password|senha|token)\s*[:=]\s*\S+/i },
	{ name: 'default administrator credential', re: /_SYSTEM\s*[/:]\s*SYS\b/ },
	{ name: 'e-mail address', re: /[\w.+-]+@[\w-]+\.[\w.-]+/ }
];

export function frontMatter(text) {
	const m = /^<!--\s*(.*?)\s*-->/s.exec(text.trimStart());
	if (!m) return null;
	const out = {};
	for (const part of m[1].split('|')) {
		const i = part.indexOf(':');
		if (i > 0) out[part.slice(0, i).trim()] = part.slice(i + 1).trim();
	}
	return out;
}

/** The article without front matter, code blocks, HTML comments and link targets. */
export function prose(text) {
	return text
		.replace(/^<!--.*?-->/s, '')
		.replace(/```[\s\S]*?```/g, ' ')
		.replace(/<!--[\s\S]*?-->/g, ' ')
		.replace(/\]\([^)]*\)/g, ']')
		.replace(/https?:\/\/\S+/g, ' ');
}

export function wordCount(text) {
	return (prose(text).match(/[\p{L}\p{N}][\p{L}\p{N}'’-]*/gu) ?? []).length;
}

export function sections(text) {
	return [...text.matchAll(/^##\s+(.+?)\s*$/gm)].map((m) => m[1]);
}

export function links(text) {
	const found = [...text.matchAll(/\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g)].map((m) => m[1]);
	return [...new Set(found)];
}

/** Every problem that does not need the network, as strings. */
export function staticProblems(text) {
	const problems = [];
	const fm = frontMatter(text);
	if (!fm) problems.push('front matter missing (first line: <!-- lang: … | status: … -->)');
	const lang = fm?.lang ?? 'en';
	const required = REQUIRED_SECTIONS[lang];
	if (!required) problems.push(`unknown lang "${lang}"`);
	const have = sections(text);
	for (const s of required ?? []) if (!have.includes(s)) problems.push(`section missing: ## ${s}`);
	const words = wordCount(text);
	if (words < WORDS.min || words > WORDS.max) problems.push(`${words} words (expected ${WORDS.min}–${WORDS.max})`);
	for (const link of links(text)) {
		if (!/^https?:\/\//.test(link) && !link.startsWith('#')) problems.push(`relative link (use an absolute URL; pasted articles lose the repository): ${link}`);
	}
	const body = text.replace(/^<!--.*?-->/s, '');
	for (const f of FORBIDDEN) {
		const m = f.re.exec(body);
		if (m) problems.push(`${f.name}: "${m[0]}"`);
	}
	if (fm?.status === 'ready' && /<!--\s*after\b/i.test(body)) problems.push('status is ready but "<!-- after … -->" markers remain');
	return problems;
}

/** Links that do not answer 2xx/3xx (GET, 10 s, one retry). */
export async function brokenLinks(text, fetchFn = fetch) {
	const broken = [];
	for (const link of links(text).filter((l) => /^https?:\/\//.test(l))) {
		let ok = false;
		for (let attempt = 0; attempt < 2 && !ok; attempt++) {
			try {
				// Some sites (the Ideas portal) refuse requests without a browser-like User-Agent.
				const res = await fetchFn(link, {
					method: 'GET',
					redirect: 'manual',
					headers: { 'User-Agent': 'Mozilla/5.0 (SentaiTask article link check)' },
					signal: AbortSignal.timeout(10_000)
				});
				ok = (res.status >= 200 && res.status < 400) || res.type === 'opaqueredirect';
			} catch {
				ok = false;
			}
		}
		if (!ok) broken.push(link);
	}
	return broken;
}
