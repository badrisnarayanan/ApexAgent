---
title: ApexAgent MCP server vs Salesforce Hosted MCP Servers
description: ApexAgent's MCP server next to the MCP servers Salesforce hosts. What each is, what Salesforce has said about billing, and when to choose which.
---

There are two ways to give AI apps such as Claude and ChatGPT an MCP server for your org. Salesforce offers its own, called **Hosted MCP Servers**. ApexAgent gives you one you deploy yourself. Both come with ready-made tools, and both let you add your own. The main differences are which kinds of tool you can add, and whether you can read and change the ready-made ones.

## At a glance

| | ApexAgent MCP server | Salesforce Hosted MCP Servers |
| --- | --- | --- |
| **What it is** | An MCP endpoint you deploy as Apex, reached through a Salesforce Site | MCP servers Salesforce runs for your org |
| **Who brings the AI model** | The client, such as Claude or ChatGPT | The client, such as Claude or ChatGPT |
| **Runs as the signed-in user** | Yes | Yes |
| **Sign-in** | OAuth with PKCE, through an External Client App | OAuth with PKCE, through an External Client App |
| **Ready-made tools** | Ten, on the Default MCP Server | Salesforce's standard servers |
| **Your own tools** | Apex classes with an invocable method | Flows, Apex invocable actions, AuraEnabled Apex, Apex REST and APIs from API Catalog, such as Named Query APIs |
| **Your own servers** | As many as you create, each with its own tools | Custom servers, each with its own tools |
| **Source of the ready-made tools** | Open. You can read and change them | Closed |
| **Record of every call** | Tool Logs in your org | Salesforce's own monitoring |
| **Support** | Community, open source | Salesforce |
| **Source code** | Yours to read and change | Closed |

## What Salesforce has said about billing

Salesforce has [announced](https://help.salesforce.com/s/articleView?language=en_US&id=005360285&type=1) that every successful call a registered AI agent makes to Salesforce, over MCP or the API, will be metered as a Headless Platform Interaction and billed in Flex Credits. Agents that use Salesforce APIs will need to be registered. The rate is still marked TBA, metering has not started, and Salesforce says it will give 30 days' notice. Sandboxes, scratch orgs and Developer Edition orgs are not metered.

That applies to an AI client calling either server, so cost is not a reason to choose one over the other. Today, each request to ApexAgent's MCP server uses one of your org's ordinary daily API requests. See [Limits](/ApexAgent/mcp/limits/) for how far that allowance goes.

Salesforce describes its Hosted MCP Servers as "intended only for customers with Flex Credits." See its [Hosted MCP Servers overview](https://developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/hosted-mcp-servers-overview.html) and the [rate card](https://www.salesforce.com/agentforce/rates/) for current terms.

## How it is built

The MCP server is built from features your org already has:

- **An Apex REST class** answers the client's requests.
- **A Salesforce Site** gives it a public URL.
- **An External Client App** signs each user in with their own Salesforce login.
- **Custom objects** hold the server's configuration and the log of every call.

## When to choose which

Both let you write your own tools in Apex and decide which tools each server exposes.

Choose **ApexAgent's MCP server** if you want:

- Ready-made tools whose source you can read, audit and change
- A log of every call as records in your org that you can report on
- The same tools your users get from ApexAgent's agent inside Salesforce

Choose **Salesforce Hosted MCP Servers** if you need:

- To expose flows, Apex REST, AuraEnabled methods or Named Query APIs as tools, not only Apex classes
- Salesforce's ready-made standard servers
- A vendor to call when something breaks

The two are not exclusive. Both can run in the same org.
