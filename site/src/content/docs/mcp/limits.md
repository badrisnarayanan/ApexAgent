---
title: Limits
description: The Salesforce limits that apply to the MCP server, and how to watch them.
---

## Daily API requests

Every request from an MCP client uses one API request from your org's daily allowance, the same allowance your other integrations use. That means each tool call, and each time the client fetches the list of tools. A typical question takes two to four tool calls.

| Edition | Requests per 24 hours |
| --- | --- |
| Enterprise | 100,000, plus 1,000 for each Salesforce user license |
| Unlimited and Performance | 100,000, plus 5,000 for each Salesforce user license |
| Developer | 15,000 |

To put that in scale: an Enterprise org with 100 users has 200,000 requests a day. If all 100 people asked 50 questions a day through an MCP client, at four tool calls each, that is 20,000 requests, a tenth of the allowance. Most orgs will never notice the usage.

It is worth a look only if your org already runs close to its allowance because of other integrations. To see where you stand, open **Setup > Company Information** and check **API Requests, Last 24 Hours**.

## Site page views

You are very unlikely to reach this limit. It is here so you know it exists.

The Endpoint URL goes through a Salesforce Site, and Salesforce counts a page view only for a request that arrives without a valid sign-in. For ApexAgent that means the sign-in handshake and nothing else:

- Tool calls from a signed-in user do **not** count, however many there are.
- Connecting a client counts as about two page views.
- Renewing a user's access token when it expires counts as about one.

Salesforce's monthly allowance is 500,000 page views for Enterprise Edition and 1,000,000 for Unlimited and Performance. Developer Edition has no page-view limit.

To put that in scale: someone who uses a connected client all day adds a handful of page views a day. A hundred such people come to roughly 10,000 a month, about 2% of the Enterprise allowance. You would need several thousand people using it all day, every working day, to come close.

Requests from anyone who has not signed in also count, since the URL is public. They get nothing back and cannot reach your data, and it would take hundreds of thousands of them in a month to matter.

If you ever want to check usage, open the Site under Setup > Sites and look at its page-view and 24-hour usage lists.
