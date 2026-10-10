---
title: Limits
description: The Salesforce limits that apply to the MCP server, and how to watch them.
---

## Daily API requests

Every tool call from an MCP client counts as one API request against your org's daily allowance. This is the limit that matters for normal use.

## Site page views

The Endpoint URL goes through a Salesforce Site, and Salesforce counts page views for requests made to a Site without a valid sign-in:

- Tool calls from a signed-in user do **not** count.
- The sign-in handshake does: about two requests each time a client connects, and about one each time a user's access token expires.

Salesforce's monthly page-view allowance is 500,000 for Enterprise Edition and 1,000,000 for Unlimited and Performance. Developer Edition has no page-view limit.

Because the URL is public, anyone can send it unauthenticated requests, and those count too. They cannot reach your data, but a very large flood could use up the allowance. To watch usage, open the Site under Setup > Sites and check its page-view and 24-hour usage lists.
