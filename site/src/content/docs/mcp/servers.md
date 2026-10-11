---
title: Configure MCP servers
description: Choose which tools a server exposes, and run more than one server for different groups.
---

An MCP server is a record in the Setup Portal with a list of tools. Setup creates one, called Default MCP Server. You can change what it exposes, or add more servers, without changing code.

## What a server record holds

| Field | What it does |
| --- | --- |
| **MCP API Name** | A short name using letters, digits, hyphens and underscores. It becomes the last part of the server's URL |
| **Endpoint URL** | Filled in for you from the API name. This is the URL a client connects to |
| **Active** | Untick to switch the server off without deleting it. Clients that try to reach it get a not-found error |
| **Description** | Your own notes on what the server is for. It is not shown to clients |

## Choose its tools

A server exposes only the tools linked to it. Each link is an **MCP Tool Map** record: open the server, and add or remove tools in its related list.

- To make a server **read-only**, leave `ApexAgentUpsertRecords` off.
- Untick **Active** on a link to take a tool away for a while without deleting the link.
- A tool you wrote yourself is added the same way. See [Add your own tool](/ApexAgent/tools/add-a-tool/).

After you change a server's tools, clients that are already connected need to refresh their tool list. In Claude, open the connector's menu and choose **Refresh tools list**.

## More than one server

Create another MCP Server record with its own API name and its own tools, and tick **Active**. A new server is inactive, and returns not-found, until you do. It gets its own URL, and a client connects to it the same way as to the first. See the client pages for [Claude](/ApexAgent/mcp/clients/claude/), [ChatGPT](/ApexAgent/mcp/clients/chatgpt/) or [another client](/ApexAgent/mcp/clients/other/).

Some ways to use this:

- A read-only server for most people, and a second one that includes the write tool for a smaller team.
- A server holding only the tools one department needs, including tools you wrote for them.
- A separate server for trying out a new tool before you add it to the main one.

Every server uses the same sign-in. Whichever server a person connects to, tools run as that person, with their own Salesforce permissions. See [Security and data](/ApexAgent/operate/security/).
