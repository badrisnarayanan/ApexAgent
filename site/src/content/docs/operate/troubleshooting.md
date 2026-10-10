---
title: Troubleshooting
description: Fixes for the problems people hit most often during setup and sign-in.
---

## Setup says "Setup did not run"

Part of the project is missing from the org. Deploy the whole `force-app` folder, then run setup again.

## Setup warns that the Site does not exist or is not active

The agent is unaffected. For MCP, activate **ApexAgent MCP Server** under Setup > Sites, then run setup again so it can fill in the server URL and assign the guest permission set.

## The agent or an MCP client shows fewer tools than expected

A tool with no generated schema is left out. Open the tool record and use **Regenerate Schema**, or run setup again, which retries every tool that has none.

## The agent replies with an authentication error

The OpenRouter key is missing or wrong. Recheck step 1 of [Set up the agent](../../agent/setup/), and confirm the user has the **ApexAgent User** permission set.

## An MCP client can't sign in

Check that the client ID is the app's Consumer Key, that the client's callback URL is allowed in the External Client App, and that the user has the **ApexAgent User** permission set.

## Sign-in fails with `invalid_scope`

The client asked for a scope the External Client App does not allow. Limit the scopes the client requests to `api` and `refresh_token`. In ChatGPT, untick **OIDC enabled**.

## A permission set wasn't assigned

Setup assigns them in background jobs. Check Setup > Apex Jobs for a failed `ApexAgentSetupPermissionQueueable`.
