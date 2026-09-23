// Generates frontend/src/lib/design/tokens.css and tokens.ts from the single source of truth:
// specs/002-canvas-ui/contracts/tokens.json (binding per spec.md "Constraints > From Design").
// Never hand-edit the generated files — edit tokens.json and re-run this script.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const sourcePath = path.resolve(
	__dirname,
	'../../specs/002-canvas-ui/contracts/tokens.json'
);
const outDir = path.resolve(__dirname, '../src/lib/design');
mkdirSync(outDir, { recursive: true });

const tokens = JSON.parse(readFileSync(sourcePath, 'utf-8'));

const px = (n) => (typeof n === 'number' ? `${n}px` : n);

function themeBlock(themeName) {
	const t = tokens.theme[themeName];
	const lines = [
		`--color-ground: ${t.ground};`,
		`--color-ground-rail: ${t.groundRail};`,
		`--color-surface: ${t.surface};`,
		`--color-card: ${t.card};`,
		`--color-card-raised: ${t.cardRaised};`,
		`--color-border: ${t.border};`,
		`--color-border-faint: ${t.borderFaint};`,
		`--color-border-strong: ${t.borderStrong};`,
		`--color-text: ${t.text};`,
		`--color-text-strong: ${t.textStrong};`,
		`--color-text-muted: ${t.textMuted};`,
		`--color-text-faint: ${t.textFaint};`,
		`--color-grid-dot: ${t.gridDot};`,
		`--color-link: ${t.link};`,
		`--color-link-hover: ${t.linkHover};`,
		`--color-focus-ring: ${t.focusRing};`,
		`--color-card-shadow: ${t.cardShadow ?? 'none'};`
	];
	for (const [state, byTheme] of Object.entries(tokens.state)) {
		if (state.startsWith('$')) continue;
		lines.push(`--state-${state}: ${byTheme[themeName]};`);
	}
	for (const [state, byTheme] of Object.entries(tokens.stateText)) {
		if (state.startsWith('$')) continue;
		lines.push(`--state-text-${state}: ${byTheme[themeName]};`);
	}
	for (const [cat, byTheme] of Object.entries(tokens.category)) {
		if (cat.startsWith('$')) continue;
		lines.push(`--category-${cat}: ${byTheme[themeName]};`);
	}
	lines.push(`--destructive-accent: ${tokens.destructive.accent[themeName]};`);
	lines.push(`--destructive-surface: ${tokens.destructive.surface[themeName]};`);
	lines.push(`--destructive-border: ${tokens.destructive.border[themeName]};`);
	lines.push(`--destructive-text: ${tokens.destructive.text[themeName]};`);
	lines.push(`--destructive-body-text: ${tokens.destructive.bodyText[themeName]};`);
	lines.push(`--warning-accent: ${tokens.warning.accent[themeName]};`);
	lines.push(`--warning-surface: ${tokens.warning.surface[themeName]};`);
	lines.push(`--warning-border: ${tokens.warning.border[themeName]};`);
	lines.push(`--warning-title: ${tokens.warning.title[themeName]};`);
	lines.push(`--warning-body: ${tokens.warning.body[themeName]};`);
	lines.push(`--edge-sequence-color: ${tokens.edge.sequence[themeName]};`);
	lines.push(`--edge-join-color: ${tokens.edge.join[themeName]};`);
	lines.push(`--edge-failed-color: ${tokens.edge.failed[themeName]};`);
	lines.push(`--edge-completed-color: ${tokens.edge.completed[themeName]};`);
	lines.push(
		`--timeline-queue-a: ${tokens.timeline.queueSegment[themeName].a};`,
		`--timeline-queue-b: ${tokens.timeline.queueSegment[themeName].b};`,
		`--timeline-queue-border: ${tokens.timeline.queueSegment[themeName].border};`
	);
	return lines.map((l) => `\t${l}`).join('\n');
}

const globalLines = [
	`--font-display: ${tokens.font.display};`,
	`--font-ui: ${tokens.font.ui};`,
	`--font-mono: ${tokens.font.mono};`,
	...Object.entries(tokens.size).map(([k, v]) => `--size-${k}: ${px(v)};`),
	...Object.entries(tokens.radius).map(([k, v]) => `--radius-${k}: ${px(v)};`),
	...Object.entries(tokens.space).map(([k, v]) => `--space-${k}: ${px(v)};`),
	...Object.entries(tokens.chrome).map(([k, v]) => `--chrome-${kebab(k)}: ${px(v)};`),
	`--edge-sequence-width: ${px(tokens.edge.sequence.width)};`,
	`--edge-join-width: ${px(tokens.edge.join.width)};`,
	`--edge-failed-width: ${px(tokens.edge.failed.width)};`,
	`--edge-failed-dasharray: ${tokens.edge.failed.dasharray};`,
	`--edge-completed-width: ${px(tokens.edge.completed.width)};`,
	`--junction-marker-size: ${px(tokens.edge.junctionMarker.size)};`,
	`--junction-marker-stroke: ${px(tokens.edge.junctionMarker.stroke)};`,
	`--handle-plain-size: ${px(tokens.handle.plain.size)};`,
	`--handle-plain-stroke: ${px(tokens.handle.plain.stroke)};`,
	`--handle-plain-radius: ${px(tokens.handle.plain.radius)};`,
	`--handle-join-size: ${px(tokens.handle.join.size)};`,
	`--handle-join-stroke: ${px(tokens.handle.join.stroke)};`,
	`--destructive-hazard-height: ${px(tokens.destructive.hazardBand.height)};`,
	`--destructive-hazard-angle: ${tokens.destructive.hazardBand.angle}deg;`,
	`--destructive-hazard-stripe: ${px(tokens.destructive.hazardBand.stripe)};`,
	`--timeline-bar-height: ${px(tokens.timeline.barHeight)};`,
	`--timeline-row-gap: ${px(tokens.timeline.rowGap)};`,
	`--timeline-label-column-width: ${px(tokens.timeline.labelColumnWidth)};`,
	`--a11y-min-hit-target: ${px(tokens.a11y.minHitTarget)};`,
	`--a11y-focus-ring-width: ${px(tokens.a11y.focusRingWidth)};`
];

function kebab(s) {
	return s.replace(/([a-z0-9])([A-Z])/g, '$1-$2').toLowerCase();
}

const css = `/* GENERATED FILE — do not hand-edit. Source: specs/002-canvas-ui/contracts/tokens.json
   Regenerate with: npm run generate:tokens */

:root {
${globalLines.map((l) => `\t${l}`).join('\n')}
\tfont-variant-numeric: tabular-nums;
}

:root[data-theme='dark'] {
${themeBlock('dark')}
}

:root[data-theme='light'] {
${themeBlock('light')}
}
`;

writeFileSync(path.join(outDir, 'tokens.css'), css);

const tsOut = `// GENERATED FILE — do not hand-edit. Source: specs/002-canvas-ui/contracts/tokens.json
// Regenerate with: npm run generate:tokens
export const tokens = ${JSON.stringify(tokens, null, 2)} as const;

export type ThemeName = 'dark' | 'light';
export type StepCategory = keyof typeof tokens.category;
export type JobState = keyof typeof tokens.state;
`;

writeFileSync(path.join(outDir, 'tokens.ts'), tsOut);

console.log('Wrote', path.join(outDir, 'tokens.css'));
console.log('Wrote', path.join(outDir, 'tokens.ts'));
