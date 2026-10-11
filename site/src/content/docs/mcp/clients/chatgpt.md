---
title: Connect ChatGPT
description: Add ApexAgent to ChatGPT as a custom connector.
---

You need two values from [Set up the MCP server](/ApexAgent/mcp/setup/): the **Endpoint URL** and the **client ID** (the External Client App's Consumer Key).

ChatGPT needs Developer Mode to add a custom connector. Create the connector with these settings:

| Setting | Value |
| --- | --- |
| Server URL | The Endpoint URL |
| Registration method | User-Defined OAuth Client |
| OAuth client ID | The Consumer Key |
| OAuth client secret | Leave empty |
| Token endpoint auth method | Leave empty |
| OIDC enabled | **Unticked** |

Before you connect, copy the **Callback URL** ChatGPT shows on that screen and add it to the External Client App's callback URLs in Salesforce: in Setup, open **External Client App Manager**, edit **ApexAgent MCP**, and add the URL to **Callback URL** under its OAuth settings. ChatGPT gives every connector its own callback URL, so repeat this for each new connector. Salesforce can take a few minutes to apply the change.

If sign-in fails with `invalid_scope`, ChatGPT is asking for scopes the app does not allow. Check that **OIDC enabled** is unticked.
