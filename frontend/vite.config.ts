import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vitest/config';

// In `npm run dev`, the SvelteKit app lives on Vite while the APIs live in the IRIS container;
// proxying keeps every call same-origin, exactly as in the container build.
const iris = 'http://localhost:52773';

export default defineConfig({
	plugins: [sveltekit()],
	server: {
		proxy: {
			'/api/admin': iris,
			'/csp/sentai/api': iris
		}
	},
	test: {
		include: ['src/**/*.test.ts']
	}
});
