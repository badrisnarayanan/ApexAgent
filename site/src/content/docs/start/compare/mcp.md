---
title: ApexAgent MCP server vs Salesforce Hosted MCP Servers
description: ApexAgent's MCP server next to the MCP servers Salesforce hosts. What each is, what each costs and when to choose which.
---

There are two ways to give AI apps such as Claude and ChatGPT an MCP server for your org. Salesforce offers its own, called **Hosted MCP Servers**. ApexAgent gives you one you deploy yourself. Both come with ready-made tools, and both let you add your own. The main difference is how you pay: Salesforce's are for customers with Flex Credits, and ApexAgent's uses none.

## At a glance

| | ApexAgent MCP server | Salesforce Hosted MCP Servers |
| --- | --- | --- |
| **What it is** | An MCP endpoint you deploy as Apex, reached through a Salesforce Site | MCP servers Salesforce runs for your org |
| **Salesforce charge** | None | For customers with Flex Credits; usage may be billed |
| **What a tool call uses** | One ordinary API request | Flex Credits |
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

## What it costs

**Salesforce Hosted MCP Servers** are, in Salesforce's words, "intended only for customers with Flex Credits and you may be billed for server usage." See its [Hosted MCP Servers overview](https://developer.salesforce.com/docs/platform/hosted-mcp-servers/guide/hosted-mcp-servers-overview.html) and the [rate card](https://www.salesforce.com/agentforce/rates/) for current prices.

**ApexAgent's MCP server** costs nothing to run. Each request from a client uses one of your org's ordinary daily API requests, and the model belongs to the app each person already uses. See [Limits](/ApexAgent/mcp/limits/) for how far that allowance goes.

## How it works without Flex Credits

Nothing here is a workaround. The MCP server is built from features your org already has:

- **An Apex REST class** answers the client's requests.
- **A Salesforce Site** gives it a public URL.
- **An External Client App** signs each user in with their own Salesforce login.
- **Custom objects** hold the server's configuration and the log of every call.

## A worked example

Take 100 people, each asking 20 questions a working day through Claude or ChatGPT, with about three tool calls a question. That is roughly 132,000 tool calls a month.

| | ApexAgent MCP server | Salesforce Hosted MCP Servers |
| --- | --- | --- |
| Salesforce charge for the month | $0 | Billed in Flex Credits |
| What it uses instead | About 6,000 of your org's API requests a day. An Enterprise org with 100 users has 200,000 a day | Flex Credits from your balance |

We cannot put a dollar figure in the right-hand column. Salesforce's [Flex Credits rate card](https://www.salesforce.com/agentforce/rates/) lists hosted MCP usage as "Headless Platform Interaction" with the rate still marked TBA. When Salesforce publishes it, we will add the comparison here.

## When to choose which

Both let you write your own tools in Apex and decide which tools each server exposes. The main reason to choose ApexAgent is cost. The other differences are how many kinds of tool you can add, and whether you can see inside the ready-made ones.

Choose **ApexAgent's MCP server** if you want:

- The most affordable way to run an MCP server for Salesforce: it costs nothing
- To connect Claude or ChatGPT without buying Flex Credits
- Ready-made tools whose source you can read, audit and change
- A log of every call as records in your org that you can report on

Choose **Salesforce Hosted MCP Servers** if you need:

- To expose flows, Apex REST, AuraEnabled methods or Named Query APIs as tools, not only Apex classes
- Salesforce's ready-made standard servers
- A vendor to call when something breaks

The two are not exclusive. Both can run in the same org.
