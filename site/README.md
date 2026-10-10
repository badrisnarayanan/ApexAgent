# ApexAgent documentation site

The site at https://badrisnarayanan.github.io/ApexAgent/, built with [Astro Starlight](https://starlight.astro.build).

```bash
npm install
npm run dev      # local preview with live reload
npm run build    # production build into dist/
```

- Docs pages are Markdown files in `src/content/docs/`. The sidebar is defined in `astro.config.mjs`.
- The landing page is `src/pages/index.astro`.
- Colours and type are in `src/styles/theme.css`.

Pushing to `main` rebuilds and publishes the site through `.github/workflows/deploy-site.yml`.
