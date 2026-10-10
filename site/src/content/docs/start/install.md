---
title: Install
description: Deploy ApexAgent to your org and run the one-time setup.
---

These steps are the same whichever part you want. Check the [prerequisites](../prerequisites/) first.

## 1. Get the code and sign in to your org

```bash
git clone https://github.com/badrisnarayanan/ApexAgent.git
cd ApexAgent
sf org login web --alias my-org --set-default
```

To sign in to a sandbox, add `--instance-url https://test.salesforce.com` to the last command.

## 2. Deploy

```bash
sf project deploy start --source-dir force-app
```

## 3. Run setup

```bash
sf apex run --file seed/setup.apex
```

Setup prints one line beginning `ApexAgent setup:` that says what it did. On a first run it:

- creates the starter configuration: 2 LLMs, 10 tools, 1 topic with 3 instructions, 1 agent (Lumen) and 1 MCP server
- assigns the **ApexAgent Admin** permission set to you
- assigns the **ApexAgent MCP Guest** permission set to the MCP Site's guest user

It is safe to run again. It never duplicates or overwrites records; a later run only finishes anything an earlier one could not.

## 4. Give your users access

Assign the **ApexAgent User** permission set to everyone who will chat with the agent or connect an MCP client. In Setup, open **Permission Sets**, open **ApexAgent User** and use **Manage Assignments**. Or from the command line:

```bash
sf org assign permset --name ApexAgent_User --on-behalf-of someone@example.com
```

## Next

Nothing is usable yet: each part needs a few more clicks in Salesforce Setup. Continue with the part you want:

- [Set up the MCP server](../../mcp/setup/)
- [Set up the agent](../../agent/setup/)
