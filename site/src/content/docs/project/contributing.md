---
title: Contributing
description: The repository layout, how to run the tests, and how to change the starter configuration.
---

## Layout

```
force-app/main/default/
  classes/ApexAgent/
    core/      shared by the agent and the MCP server
    tools/     the built-in tools
    agent/     agent only
    mcp/       MCP server only
    setup/     the org setup run by seed/setup.apex
    tests/     all test classes
  staticresources/ApexAgentSeedData/
               the starter configuration that setup loads
seed/
  setup.apex       what installers run
  export-seed.js   regenerates the starter configuration from an org
site/              this documentation site
```

## Run the tests

```bash
sf apex run test --class-names ApexAgentToolExecutorTest --synchronous
```

## Change the starter configuration

Edit the records in your org, then pull them into the repo:

```bash
npm run export-seed
```

This rewrites `staticresources/ApexAgentSeedData/`: `data.json` plus one markdown file per instruction. Review the diff before committing, because everything in that folder ships to every installer.

## License

ApexAgent is released under the [MIT license](https://github.com/badrisnarayanan/ApexAgent/blob/main/LICENSE).
