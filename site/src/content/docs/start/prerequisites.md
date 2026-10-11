---
title: Prerequisites
description: What you need before installing ApexAgent.
---

## For everything

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) and [Git](https://git-scm.com/downloads). You run a few commands in a terminal, or use VS Code with the Salesforce Extension Pack instead
- A Salesforce org where you are a System Administrator
- **Developer, Enterprise, Performance or Unlimited Edition.** The MCP server uses a Salesforce Site, which other editions do not have.
- Nothing in the org already using names that start with `ApexAgent`. A deploy overwrites components with the same name.

If you are trying ApexAgent for the first time, use a sandbox or a free [Developer Edition org](https://developer.salesforce.com/signup) before you deploy to production.

## Only for the MCP server

- An MCP client that supports remote servers with OAuth and lets you enter a client ID, such as Claude or ChatGPT

## Only for the agent

- An API key from an AI model provider. [OpenRouter](https://openrouter.ai) is the quickest, because its connection is already set up. Any OpenAI-compatible provider works; see [Use a different provider](/ApexAgent/agent/providers/)
