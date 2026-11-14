// OnlySwitch's automatic appearance fallback. Runs entirely in WebKit's isolated client world.
(() => {
    if (typeof DarkReader === 'undefined') return;

    // Extra stylesheet/image requests are optional in Dark Reader. Never give this adapter a
    // native networking bridge or let it fetch resources the page has not already exposed.
    const rejectResourceRequest = async () => {
        throw new Error('Additional appearance resource requests are disabled');
    };
    // This global belongs only to the isolated client world; the site's fetch is unchanged.
    // Dark Reader's same-origin CSS path otherwise bypasses its custom fetch method.
    globalThis.fetch = rejectResourceRequest;
    DarkReader.setFetchMethod(rejectResourceRequest);

    const preference = matchMedia('(prefers-color-scheme: dark)');
    let pendingUpdate;

    function color(value) {
        const match = value.match(/^rgba?\(([^)]+)\)$/);
        if (!match) return null;
        const channels = match[1].split(/[\s,/]+/).map(Number);
        return {rgb: channels.slice(0, 3), alpha: channels[3] ?? 1};
    }

    function composite(foreground, background) {
        if (!foreground) return background;
        return foreground.rgb.map((channel, index) =>
            channel * foreground.alpha + background[index] * (1 - foreground.alpha));
    }

    function hasNativeDarkBackground() {
        const rootStyle = getComputedStyle(document.documentElement);
        const bodyStyle = document.body ? getComputedStyle(document.body) : rootStyle;
        const root = color(rootStyle.backgroundColor);
        const body = color(bodyStyle.backgroundColor);
        const hasExplicitBackground = (root?.alpha ?? 0) > 0 || (body?.alpha ?? 0) > 0;
        if (!hasExplicitBackground && rootStyle.colorScheme.split(/\s+/).includes('dark')) {
            return true;
        }
        const background = composite(body, composite(root, [255, 255, 255]));
        const linear = background.map(channel => {
            const normalized = channel / 255;
            return normalized <= 0.04045 ? normalized / 12.92 : ((normalized + 0.055) / 1.055) ** 2.4;
        });
        return 0.2126 * linear[0] + 0.7152 * linear[1] + 0.0722 * linear[2] < 0.2;
    }

    function applyAppearance(isDark) {
        // Measure the original styles, so our generated dark background can never be mistaken
        // for native support. Theme changes also restore the site's exact original styles.
        if (DarkReader.isEnabled()) DarkReader.disable();
        if (!isDark || !document.documentElement || hasNativeDarkBackground()) return;
        DarkReader.enable({brightness: 100, contrast: 100, sepia: 0}, {
            ignoreImageAnalysis: ['*'],
            disableStyleSheetsProxy: true,
            disableCustomElementRegistryProxy: true
        });
    }

    function updateAppearance() {
        applyAppearance(preference.matches);
    }

    function scheduleUpdate() {
        clearTimeout(pendingUpdate);
        // Let native media-query listeners and styles settle before checking the site's theme.
        pendingUpdate = setTimeout(updateAppearance, 0);
    }

    // Retain the controller for explicit host updates throughout this document's lifetime.
    globalThis.onlySwitchBrowserAppearance = {preference, updateAppearance, apply: applyAppearance};
    // Handle appearance changes immediately: background pages may throttle their timers.
    preference.addEventListener('change', updateAppearance);
    window.addEventListener('load', scheduleUpdate, {once: true});
    scheduleUpdate();
})();
