<script lang="ts">
import { onMount } from "svelte";

export let repo: string;
export let repoId: string;
export let category: string;
export let categoryId: string;

let host: HTMLDivElement;
let loaded = false;
let failed = false;

function currentTheme() {
	return document.documentElement.classList.contains("dark") ? "dark" : "light";
}

function sendTheme() {
	const frame = host?.querySelector<HTMLIFrameElement>("iframe.giscus-frame");
	frame?.contentWindow?.postMessage(
		{ giscus: { setConfig: { theme: currentTheme() } } },
		"https://giscus.app",
	);
}

onMount(() => {
	if (!repo || !repoId || !category || !categoryId) {
		failed = true;
		return;
	}

	const script = document.createElement("script");
	script.src = "https://giscus.app/client.js";
	script.async = true;
	script.crossOrigin = "anonymous";
	script.dataset.repo = repo;
	script.dataset.repoId = repoId;
	script.dataset.category = category;
	script.dataset.categoryId = categoryId;
	script.dataset.mapping = "pathname";
	script.dataset.strict = "1";
	script.dataset.reactionsEnabled = "1";
	script.dataset.emitMetadata = "0";
	script.dataset.inputPosition = "top";
	script.dataset.theme = currentTheme();
	script.dataset.lang = "id";
	script.dataset.loading = "lazy";
	script.addEventListener("load", () => (loaded = true), { once: true });
	script.addEventListener("error", () => (failed = true), { once: true });
	host.appendChild(script);

	const observer = new MutationObserver(sendTheme);
	observer.observe(document.documentElement, {
		attributes: true,
		attributeFilter: ["class"],
	});

	return () => observer.disconnect();
});
</script>

<section
	class="card-base mb-4 overflow-hidden p-6 text-black/90 md:p-9 dark:text-white/90"
	aria-labelledby="discussion-heading"
	data-pagefind-ignore
>
	<h2 id="discussion-heading" class="mb-2 text-2xl font-bold">Ruang diskusi</h2>
	<p class="mb-7 max-w-[70ch] leading-7 text-black/70 dark:text-white/70">
		Masuk dengan GitHub untuk berkomentar, membalas, atau memberi reaksi. Percakapan ini dikelola melalui GitHub Discussions.
	</p>

	{#if !loaded && !failed}
		<p class="giscus-state" role="status">Memuat percakapan…</p>
	{/if}
	{#if failed}
		<div class="giscus-state" role="alert">
			<p>Komentar belum dapat dimuat.</p>
			<a
				class="discussion-link"
				href={`https://github.com/${repo}/discussions`}
				target="_blank"
				rel="noopener noreferrer"
			>
				Buka percakapan di GitHub
			</a>
		</div>
	{/if}
	<div bind:this={host} class="giscus-host min-w-0" aria-live="polite"></div>
</section>

<style>
	.giscus-host :global(.giscus-frame) {
		width: 100%;
		min-height: 160px;
		border: 0;
		color-scheme: light dark;
	}
	.giscus-state {
		padding-block: 1rem;
		color: color-mix(in oklch, currentColor 72%, transparent);
	}
	.discussion-link {
		display: inline-flex;
		min-height: 44px;
		align-items: center;
		color: var(--primary);
		text-decoration: underline;
		text-underline-offset: 4px;
	}
	.discussion-link:focus-visible {
		outline: 2px solid var(--primary);
		outline-offset: 3px;
		border-radius: 0.25rem;
	}
</style>
