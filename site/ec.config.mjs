// Code block styling. Starlight reads this file for Markdown code blocks and the <Code> component.

/**
 * Turns a hex colour into the grey of the same brightness, so syntax
 * highlighting keeps its contrast steps without bringing in colour.
 * @param {string} hex
 */
function toGrey(hex) {
	const match = /^#([0-9a-f]{6})([0-9a-f]{2})?$/i.exec(hex);
	if (!match) return hex;
	const [r, g, b] = [0, 2, 4].map((i) => parseInt(match[1].slice(i, i + 2), 16));
	const level = Math.round(0.2126 * r + 0.7152 * g + 0.0722 * b)
		.toString(16)
		.padStart(2, '0');
	return `#${level}${level}${level}${match[2] ?? ''}`;
}

/** @type {import('@astrojs/starlight/expressive-code').StarlightExpressiveCodeOptions} */
export default {
	themes: ['min-dark', 'min-light'],
	customizeTheme: (theme) => {
		for (const rule of theme.settings) {
			if (rule.settings.foreground) {
				rule.settings.foreground = toGrey(rule.settings.foreground);
			}
		}
		return theme;
	},
	defaultProps: { frame: 'none' },
	styleOverrides: {
		borderRadius: '0.75rem',
		codeBackground: 'var(--sl-color-gray-6)',
		frames: { frameBoxShadowCssValue: 'none' },
	},
};
