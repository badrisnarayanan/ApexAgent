---
title: Connect a client
description: Settings for connecting Claude, ChatGPT, MCP Inspector and other MCP clients to ApexAgent.
---

Every client needs two values from [Set up the MCP server](../setup/): the **Endpoint URL** and the **client ID** (the External Client App's Consumer Key).

## Claude

Add a custom connector with the Endpoint URL and, under the advanced settings, the client ID. Sign in with your Salesforce login when prompted.

Claude's callback URL, `https://claude.ai/api/mcp/auth_callback`, is already allowed in the External Client App.

## ChatGPT

ChatGPT needs Developer Mode to add a custom connector. Create the connector with these settings:

| Setting | Value |
| --- | --- |
| Server URL | The Endpoint URL |
| Registration method | User-Defined OAuth Client |
| OAuth client ID | The Consumer Key |
| OAuth client secret | Leave blank |
| Token endpoint auth method | Leave empty |
| OIDC enabled | **Unticked** |

Before you connect, copy the **Callback URL** ChatGPT shows on that screen and add it to the External Client App's callback URLs in Salesforce: in Setup, open **External Client App Manager**, edit **ApexAgent MCP**, and add the URL to **Callback URL** under its OAuth settings. ChatGPT gives every connector its own callback URL, so repeat this for each new connector. Salesforce can take a few minutes to apply the change.

If sign-in fails with `invalid_scope`, ChatGPT is asking for scopes the app does not allow. Check that **OIDC enabled** is unticked.

## MCP Inspector

Use the Endpoint URL with the client ID. Its callback URL, `http://localhost:6274/oauth/callback`, is already allowed in the External Client App.

## Another client

The client must let you enter an OAuth client ID. Salesforce does not let clients register themselves.

1. Add the client's callback URL to the External Client App's OAuth settings.
2. Connect with the Endpoint URL and the client ID.
3. If the client requests extra scopes, limit them to `api` and `refresh_token`.
