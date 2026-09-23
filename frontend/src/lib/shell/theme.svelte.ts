// FR-038: the theme is only ever the `data-theme` attribute on :root; components read CSS
// tokens, never this value, to pick a colour.
import type { ThemeName } from '$lib/design/tokens';

const STORAGE_KEY = 'sentai.theme';

function readStored(): ThemeName {
	try {
		return localStorage.getItem(STORAGE_KEY) === 'light' ? 'light' : 'dark';
	} catch {
		return 'dark';
	}
}

class Theme {
	current = $state<ThemeName>('dark');

	init(): void {
		this.set(readStored());
	}

	set(name: ThemeName): void {
		this.current = name;
		document.documentElement.dataset.theme = name;
		try {
			localStorage.setItem(STORAGE_KEY, name);
		} catch {
			// Private windows can refuse storage; the theme still applies for this page.
		}
	}
}

export const theme = new Theme();
