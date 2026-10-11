---
title: Connect another client
description: Every value an MCP client might ask for when you connect it to ApexAgent, and what to enter.
---

Clients differ in what they ask for. Some need two values, some show a dozen fields. This page lists every setting you are likely to meet and what to put in it.

## Before you start

The client must support **remote MCP servers** with **OAuth**, and must let you **enter your own OAuth client ID**. Salesforce does not let a client register itself, so a client that offers only automatic registration cannot connect.

It must also speak the `2026-07-28` revision of the MCP protocol. Current versions of Claude and ChatGPT do. An older client that has not been updated may fail to connect even with the right settings.

You need two values from [Set up the MCP server](/ApexAgent/mcp/setup/): the **Endpoint URL** and the **client ID** (the External Client App's Consumer Key).

## 1. Allow the client's callback URL

During sign-in, Salesforce sends the user back to a URL the client owns, and only to URLs you have allowed. Find the client's callback URL, sometimes called a redirect URI, in its connector screen or its documentation.

In Setup, open **External Client App Manager**, edit **ApexAgent MCP**, and add the URL to **Callback URL** under its OAuth settings, on a line of its own. Salesforce can take a few minutes to apply the change.

Claude's callback URL is already there. Some clients, ChatGPT among them, give every connector its own callback URL, so you add one each time.

## 2. Fill in the client's settings

Most clients need only the first two rows. Use the rest if the client shows the field.

| The client asks for | Enter |
| --- | --- |
| Server URL, MCP URL, endpoint | The Endpoint URL |
| OAuth client ID | The Consumer Key |
| OAuth client secret | Leave empty |
| Registration method | The option for **your own or a pre-registered client**. Not automatic or dynamic registration |
| Transport | HTTP, also called Streamable HTTP. Not SSE, and not stdio |
| Authentication type | OAuth 2.0, authorization code with PKCE |
| Authorization URL | `https://<your-my-domain>.my.salesforce.com/services/oauth2/authorize` |
| Token URL | `https://<your-my-domain>.my.salesforce.com/services/oauth2/token` |
| Scopes | `api refresh_token` |
| Token endpoint auth method | None, or leave empty. There is no secret to send |
| PKCE | On, with method `S256` |
| OpenID Connect, OIDC | Off |

A client that follows the MCP standard finds the authorization and token URLs by itself from the Endpoint URL, so you usually do not type them. Your My Domain name is the first part of your Salesforce address in the browser.

## 3. Connect and sign in

Start the connection. The client opens a Salesforce login page; sign in as yourself. Each person who uses the client signs in with their own Salesforce login and needs the **ApexAgent User** permission set.

When it connects, the client lists the tools the server exposes.

## If it does not connect

| What you see | Likely cause |
| --- | --- |
| `redirect_uri_mismatch` | The client's callback URL is not in the External Client App, or the change has not applied yet. Wait a few minutes and try again |
| `invalid_scope` | The client asked for a scope other than `api` and `refresh_token`. Turn off OpenID Connect, or set the scopes by hand |
| `invalid_client_id` | The client ID is not the Consumer Key, or it was pasted with a space |
| The client says the server does not support registration | It is trying to register itself. Choose the option to enter your own client ID |
| Sign-in works, then the user is refused | The user does not have the **ApexAgent User** permission set |
| Connected, but no tools are listed | The server has no active tools linked to it. See [Configure MCP servers](/ApexAgent/mcp/servers/) |

More in [Troubleshooting](/ApexAgent/operate/troubleshooting/).

While you are in the External Client App, change its **Contact Email** from the placeholder `admin@example.com` to your own. It is only the contact shown for the app; sign-in works either way.
