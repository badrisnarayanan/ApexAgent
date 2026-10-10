// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';

const site = 'https://badrisnarayanan.github.io';
const base = '/ApexAgent';

export default defineConfig({
	site,
	base,
	integrations: [
		starlight({
			title: 'ApexAgent',
			description:
				'An AI agent and an MCP server for Salesforce, built in plain Apex. No Agentforce license. No Flex Credits.',
			logo: {
				light: './src/assets/logo-black.svg',
				dark: './src/assets/logo-white.svg',
				alt: '',
			},
			favicon: '/favicon.svg',
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/badrisnarayanan/ApexAgent' },
			],
			editLink: {
				baseUrl: 'https://github.com/badrisnarayanan/ApexAgent/edit/main/site/',
			},
			components: {
				PageTitle: './src/components/PageTitle.astro',
				SocialIcons: './src/components/SocialIcons.astro',
			},
			customCss: [
				'@fontsource-variable/dm-sans/opsz.css',
				'@fontsource-variable/jetbrains-mono/index.css',
				'./src/styles/theme.css',
			],
			head: [
				{ tag: 'meta', attrs: { property: 'og:image', content: `${site}${base}/og.png` } },
				{ tag: 'meta', attrs: { name: 'twitter:card', content: 'summary_large_image' } },
			],
			sidebar: [
				{
					label: 'Start',
					items: [
						{ label: 'What ApexAgent is', slug: 'start/overview' },
						{ label: 'Prerequisites', slug: 'start/prerequisites' },
						{ label: 'Install', slug: 'start/install' },
					],
				},
				{
					label: 'MCP server',
					items: [
						{ label: 'Set up the MCP server', slug: 'mcp/setup' },
						{ label: 'Connect a client', slug: 'mcp/clients' },
						{ label: 'Limits', slug: 'mcp/limits' },
					],
				},
				{
					label: 'Agent',
					items: [
						{ label: 'Set up the agent', slug: 'agent/setup' },
						{ label: 'Use a different model', slug: 'agent/models' },
					],
				},
				{
					label: 'Tools',
					items: [
						{ label: 'Built-in tools', slug: 'tools/built-in' },
						{ label: 'Add your own tool', slug: 'tools/add-a-tool' },
					],
				},
				{
					label: 'Operate',
					items: [
						{ label: 'Logs and dashboards', slug: 'operate/logs' },
						{ label: 'Troubleshooting', slug: 'operate/troubleshooting' },
					],
				},
				{
					label: 'Project',
					items: [
						{ label: "How it's organised", slug: 'project/organisation' },
						{ label: 'Contributing', slug: 'project/contributing' },
					],
				},
			],
		}),
	],
});
