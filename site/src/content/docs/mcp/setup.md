---
title: Set up the MCP server
description: Turn your Salesforce org into an MCP server that Claude, ChatGPT and other clients can connect to.
---

[MCP](https://modelcontextprotocol.io) (Model Context Protocol) is an open standard that lets an AI client call tools hosted somewhere else. ApexAgent turns your org into an MCP server. Once a client is connected, the person using it can ask things like "what fields are on Opportunity?" or "show me my open cases", and the client calls the tools in your org to answer.

The AI model belongs to the client. ApexAgent only serves the tools, so **no OpenRouter key is needed**.

[Install ApexAgent](../../start/install/) before you start.

## 1. Find your server URL

From the App Launcher, open the **ApexAgent Setup Portal** app, go to the **MCP Servers** tab and open **Default MCP Server**. Copy its **Endpoint URL**. It looks like:

```
https://<your-domain>.my.salesforce-sites.com/services/apexrest/ApexAgent/mcp/default
```

## 2. Get the OAuth client ID

In Setup, open **External Client App Manager**, open **ApexAgent MCP**, and copy the **Consumer Key** from its OAuth settings. This is the client ID your MCP client asks for. No client secret is needed: the app uses PKCE.

While you are there, edit the app and change its **Contact Email** from the placeholder `admin@example.com` to your own. It is only the contact shown for the app; sign-in works either way.

## 3. Connect your client

Add a remote MCP server in your client, with the server URL from step 1 and the client ID from step 2. When prompted, sign in with your Salesforce login.

[Connect a client](../clients/) has the settings for Claude, ChatGPT, MCP Inspector and other clients.

## Who can connect

Only users with the **ApexAgent User** permission set. The app is set to admin-approved users, pre-authorised through that permission set.

## More than one server

Create more MCP Server records, each with its own API name and its own set of tools. Each gets its own URL, so you can give different clients different tools.
