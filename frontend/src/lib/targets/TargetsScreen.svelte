<script lang="ts">
	import { untrack } from 'svelte';
	import { api } from '$lib/api/client';
	import { session } from '$lib/api/session.svelte';
	import { refusalText } from '$lib/catalog/catalog';
	import type { TargetStatusView, TargetView } from './targets';

	// Target servers (spec 009 US1) over the spec 008 API. Every value and every refusal is the
	// API's; the password typed to read a target's state is sent once and cleared, and the target's
	// tokens are dropped as soon as the state is read (nothing kept, FR-005).
	let {
		targetParam,
		onselect,
		onchanged
	}: {
		/** The `target` query value: the target shown in the pane, or null. */
		targetParam: string | null;
		onselect: (name: string | null) => void;
		/** Targets changed: the flow editor re-reads them for *Run on*. */
		onchanged: () => void;
	} = $props();

	type List = { name: 'loading' } | { name: 'ready'; targets: TargetView[] } | { name: 'refused'; message: string };
	let list = $state<List>({ name: 'loading' });
	let adding = $state(false);

	// Pane state, reset whenever the selection changes.
	let form = $state({ name: '', address: '', description: '' });
	let formError = $state<string | null>(null);
	let busy = $state(false);
	let confirmingDelete = $state(false);
	let password = $state('');
	let signInError = $state<string | null>(null);
	let status = $state<TargetStatusView | null>(null);

	const selected = $derived(list.name === 'ready' && targetParam ? (list.targets.find((t) => t.name === targetParam) ?? null) : null);

	$effect(() => {
		untrack(() => void load());
	});

	$effect(() => {
		const current = selected;
		untrack(() => {
			formError = null;
			signInError = null;
			status = null;
			password = '';
			confirmingDelete = false;
			if (current) {
				adding = false;
				form = { name: current.name, address: current.baseUrl, description: current.description };
			}
		});
	});

	async function load() {
		const result = await api.listTargets();
		list = result.ok ? { name: 'ready', targets: result.value } : { name: 'refused', message: refusalText(result.error) };
	}

	function startAdding() {
		onselect(null);
		adding = true;
		form = { name: '', address: '', description: '' };
		formError = null;
	}

	async function save() {
		busy = true;
		const result = selected
			? await api.updateTarget(selected.name, { baseUrl: form.address, description: form.description })
			: await api.createTarget({ name: form.name, baseUrl: form.address, description: form.description });
		busy = false;
		if (!result.ok) {
			formError = refusalText(result.error);
			return;
		}
		formError = null;
		await load();
		onchanged();
		onselect(result.value.name);
	}

	async function setOnline(online: boolean) {
		if (!selected) return;
		busy = true;
		const result = await api.setTargetOnline(selected.name, online);
		busy = false;
		if (!result.ok) {
			formError = refusalText(result.error);
			return;
		}
		await load();
		onchanged();
	}

	async function remove() {
		if (!selected) return;
		busy = true;
		const result = await api.deleteTarget(selected.name);
		busy = false;
		if (!result.ok) {
			formError = refusalText(result.error);
			return;
		}
		onselect(null);
		await load();
		onchanged();
	}

	/** Sign in to the target (as the signed-in operator), read its state, drop the tokens. */
	async function readState(event: SubmitEvent) {
		event.preventDefault();
		if (!selected) return;
		busy = true;
		signInError = null;
		status = null;
		const typed = password;
		password = '';
		const signedIn = await api.signInTarget(selected.name, typed);
		if (!signedIn.ok) {
			busy = false;
			signInError = refusalText(signedIn.error);
			return;
		}
		const read = await api.targetStatus(selected.name, signedIn.value.accessToken);
		busy = false;
		if (read.ok) status = read.value;
		else signInError = refusalText(read.error);
	}
</script>

<section class="targets" aria-labelledby="targets-title">
	<header class="head">
		<h1 id="targets-title">Targets</h1>
		{#if list.name === 'ready'}
			<span class="count">{list.targets.length} registered</span>
		{/if}
		<span class="spacer"></span>
		<button type="button" class="secondary" onclick={() => load()}>Refresh</button>
		<button type="button" class="primary" onclick={startAdding}>Add target</button>
	</header>

	<div class="body">
		{#if list.name === 'loading'}
			<p class="message">Reading the registered targets…</p>
		{:else if list.name === 'refused'}
			<p class="message" role="alert">{list.message}</p>
		{:else}
			<div class="table-wrap">
				<table>
					<thead>
						<tr><th scope="col">Name</th><th scope="col">Address</th><th scope="col">Description</th><th scope="col">State</th></tr>
					</thead>
					<tbody>
						{#each list.targets as target (target.name)}
							<tr
								data-testid="target-row"
								data-name={target.name}
								class:selected={targetParam === target.name}
								onclick={() => onselect(target.name)}
							>
								<td data-col="name">
									<button type="button" class="row-open" onclick={(e) => { e.stopPropagation(); onselect(target.name); }}>
										<span class="base-mark" aria-hidden="true">◆</span>{target.name}
									</button>
								</td>
								<td data-col="address" class="mono">{target.baseUrl}</td>
								<td data-col="description">{target.description}</td>
								<td data-col="online"><span class="mark" class:offline={!target.online}>{target.online ? 'online' : 'offline'}</span></td>
							</tr>
						{:else}
							<tr><td colspan="4" class="message">No target registered yet.</td></tr>
						{/each}
					</tbody>
				</table>
			</div>
		{/if}

		{#if adding || selected}
			<section class="pane" aria-label="Target detail">
				<header class="pane-head">
					<h2>{selected ? selected.name : 'New target'}</h2>
					{#if selected}<span class="sub mono">{selected.baseUrl}</span>{/if}
					<button type="button" class="quiet close" aria-label="Close detail" onclick={() => { adding = false; onselect(null); }}>✕</button>
				</header>

				<form class="fields" onsubmit={(e) => { e.preventDefault(); void save(); }}>
					{#if !selected}
						<label for="target-name">Name</label>
						<input id="target-name" class="mono" bind:value={form.name} spellcheck="false" autocomplete="off" />
					{/if}
					<label for="target-address">Address</label>
					<input id="target-address" class="mono" bind:value={form.address} placeholder="https://host:port" spellcheck="false" autocomplete="off" />
					<label for="target-description">Description</label>
					<input id="target-description" bind:value={form.description} autocomplete="off" />
					{#if formError}<p class="error" role="alert" data-testid="target-error">{formError}</p>{/if}
					<div class="actions">
						<button type="submit" class="primary" disabled={busy}>Save target</button>
						{#if selected}
							<button type="button" class="secondary" disabled={busy} onclick={() => setOnline(!selected.online)}>
								{selected.online ? 'Set offline' : 'Set online'}
							</button>
							{#if confirmingDelete}
								<button type="button" class="danger" disabled={busy} onclick={remove}>Delete {selected.name}</button>
								<button type="button" class="quiet" onclick={() => (confirmingDelete = false)}>Keep it</button>
							{:else}
								<button type="button" class="quiet" onclick={() => (confirmingDelete = true)}>Delete target</button>
							{/if}
						{/if}
					</div>
				</form>

				{#if selected}
					<form class="state" onsubmit={readState}>
						<h3>Live state</h3>
						<p class="hint">Signs you in to {selected.name} for this one read; the password and the target's tokens are not kept.</p>
						<label for="target-password">Password for {session.user} on {selected.name}</label>
						<input id="target-password" type="password" autocomplete="current-password" bind:value={password} />
						<button type="submit" class="secondary" disabled={busy || password === ''}>{busy ? 'Reading…' : 'Read state'}</button>
						{#if signInError}<p class="error" role="alert" data-testid="target-signin-error">{signInError}</p>{/if}
					</form>

					{#if status}
						<div class="status" data-testid="target-status">
							{#if status.kind === 'reachable'}
								<dl>
									<dt>State</dt><dd data-testid="status-reachable">reachable</dd>
									<dt>Version</dt><dd class="mono" data-testid="status-version">{status.version}</dd>
									<dt>Signed in as</dt><dd class="mono" data-testid="status-user">{status.user}</dd>
									<dt>Read at</dt><dd class="mono">{status.readAt}</dd>
								</dl>
								<h4>Work Queue Manager categories</h4>
								<table class="categories">
									<thead><tr><th>Name</th><th>Default</th><th>Max active</th><th>Max</th><th>Max total</th><th>Always queue</th></tr></thead>
									<tbody>
										{#each status.categories as c, i (i)}
											<tr data-testid="target-category">
												<td>{c.Name}</td><td>{c.DefaultWorkers}</td><td>{c.MaxActiveWorkers}</td><td>{c.MaxWorkers}</td><td>{c.MaxTotalWorkers}</td><td>{String(c.AlwaysQueue)}</td>
											</tr>
										{/each}
									</tbody>
								</table>
							{:else if status.kind === 'unreachable'}
								<p class="error" data-testid="target-status-unreachable">unreachable — {status.transportError}</p>
							{:else}
								<p class="error" data-testid="target-status-refused">{status.text}</p>
							{/if}
						</div>
					{/if}
				{/if}
			</section>
		{/if}
	</div>
</section>

<style>
	.targets {
		display: flex;
		flex-direction: column;
		flex-grow: 1;
		min-height: 0;
		background: var(--color-ground);
		color: var(--color-text);
	}

	.head {
		display: flex;
		align-items: center;
		gap: var(--space-section);
		padding: 10px var(--space-section);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border-faint);
	}

	h1 {
		margin: 0;
		font-size: var(--size-title);
		font-weight: 600;
	}

	.count {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.spacer {
		flex-grow: 1;
	}

	.body {
		display: flex;
		flex-grow: 1;
		min-height: 0;
	}

	.table-wrap {
		flex-grow: 1;
		min-width: 0;
		overflow: auto;
		background: var(--color-card);
	}

	table {
		width: 100%;
		border-collapse: collapse;
		font-size: var(--size-body);
	}

	th {
		text-align: left;
		font-size: var(--size-micro);
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-text-muted);
		background: var(--color-surface);
		border-bottom: 1px solid var(--color-border);
		padding: 9px 10px;
	}

	td {
		border-bottom: 1px solid var(--color-border-faint);
		padding: 9px 10px;
	}

	tbody tr {
		cursor: pointer;
	}

	tbody tr:hover,
	tr.selected {
		background: var(--color-card-raised);
	}

	tr.selected {
		box-shadow: inset 3px 0 0 var(--color-text);
	}

	.row-open {
		display: inline-flex;
		align-items: center;
		gap: 6px;
		font: inherit;
		color: inherit;
		background: none;
		border: 0;
		padding: 0;
		cursor: pointer;
	}

	.base-mark {
		font-size: var(--size-micro);
		color: var(--color-link);
	}

	.mono {
		font-family: var(--font-mono);
		font-size: var(--size-caption);
	}

	.mark {
		font-family: var(--font-mono);
		font-size: var(--size-micro);
		font-weight: 600;
		letter-spacing: 0.06em;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-chip);
		padding: 2px 6px;
	}

	.mark.offline {
		color: var(--color-text-muted);
		border-style: dashed;
	}

	.message {
		padding: var(--space-section);
		font-size: var(--size-body);
		color: var(--color-text-muted);
	}

	.pane {
		display: flex;
		flex-direction: column;
		gap: 12px;
		width: 460px;
		flex-shrink: 0;
		overflow: auto;
		padding: 12px var(--space-section);
		background: var(--color-surface);
		border-left: 1px solid var(--color-border);
	}

	.pane-head {
		display: flex;
		flex-wrap: wrap;
		align-items: baseline;
		gap: 8px;
	}

	h2 {
		margin: 0;
		font-size: var(--size-title);
		font-weight: 600;
	}

	.sub {
		color: var(--color-text-muted);
	}

	.close {
		margin-left: auto;
	}

	h3,
	h4 {
		margin: 4px 0 0;
		font-size: var(--size-caption);
		font-weight: 700;
		letter-spacing: 0.08em;
		text-transform: uppercase;
		color: var(--color-text-muted);
	}

	.fields,
	.state {
		display: flex;
		flex-direction: column;
		gap: 6px;
	}

	label {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	input {
		font: inherit;
		font-size: var(--size-body);
		color: var(--color-text);
		background: var(--color-ground);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-control);
		padding: 7px 9px;
	}

	.hint {
		margin: 0;
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	.actions {
		display: flex;
		flex-wrap: wrap;
		gap: 8px;
		margin-top: 4px;
	}

	button {
		font: inherit;
		font-size: var(--size-body);
		border-radius: var(--radius-control);
		padding: 6px 12px;
		cursor: pointer;
	}

	.primary {
		font-weight: 600;
		color: var(--color-ground);
		background: var(--color-text);
		border: 1px solid var(--color-text);
	}

	.secondary {
		font-weight: 500;
		color: var(--color-text);
		background: var(--color-card);
		border: 1px solid var(--color-border);
	}

	.quiet {
		color: var(--color-text-muted);
		background: transparent;
		border: 1px solid var(--color-border);
	}

	.danger {
		font-weight: 600;
		color: var(--destructive-text);
		background: var(--destructive-surface);
		border: 1px solid var(--destructive-accent);
	}

	button:disabled {
		opacity: 0.45;
		cursor: default;
	}

	.state .secondary {
		align-self: flex-start;
	}

	.error {
		margin: 0;
		font-size: var(--size-body);
		color: var(--destructive-text);
		overflow-wrap: anywhere;
	}

	.status dl {
		display: grid;
		grid-template-columns: 110px minmax(0, 1fr);
		gap: 6px 10px;
		margin: 0;
		font-size: var(--size-body);
	}

	dt {
		font-size: var(--size-caption);
		color: var(--color-text-muted);
	}

	dd {
		margin: 0;
		overflow-wrap: anywhere;
	}

	.categories {
		font-family: var(--font-mono);
		font-size: var(--size-micro);
	}

	.categories th,
	.categories td {
		padding: 4px;
	}
</style>
