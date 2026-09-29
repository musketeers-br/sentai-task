<script lang="ts">
	// Spec 011 US5 (FR-017): shown before a cancel that ends a running platform job.
	const WHY = 'https://github.com/musketeers-br/sentai-task/blob/master/docs/limitations.md#cancel-alert';
</script>

<p class="alert-notice" data-testid="cancel-alert-notice">
	IRIS records a cancelled platform job as an alert (severity 2), so the instance may report "unhealthy"
	until the alert is cleared. The run and the instance are fine.
	<a href={WHY} target="_blank" rel="noopener noreferrer">Why</a>
</p>

<style>
	.alert-notice {
		margin: 0 0 16px;
		padding: 9px 11px;
		font-size: var(--size-caption);
		line-height: 1.5;
		color: var(--color-text);
		background: var(--warning-surface);
		border: 1px solid var(--warning-border);
		border-radius: var(--radius-control);
	}

	.alert-notice a {
		color: var(--color-text);
		font-weight: 600;
	}
</style>
