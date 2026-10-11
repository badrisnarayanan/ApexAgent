---
title: Security and data
description: Who can see what through ApexAgent, what is logged, and where your data goes.
---

ApexAgent adds no new way into your data. It works inside the permissions your users already have, records what it does, and sends data only to the AI provider you choose.

## Every tool runs as the signed-in user

A tool call is made by a person: the user chatting with the agent, or the user who signed in from Claude or ChatGPT. The tool runs as that person.

- **Sharing rules apply.** Every tool class is declared `with sharing`. A user finds only the records they could open in Salesforce.
- **Object and field permissions apply.** The record tools read and save in user mode, so Salesforce checks object permissions and field-level security on every query and every save. A field a user cannot see is not returned. A record they cannot edit is not changed.
- **Nothing is elevated.** There is no integration user and no shared service account. Two people asking the same question can get different answers, because they have different access.

### Two tools that read the user's own details

`ApexAgentGetCurrentUser` and `ApexAgentGetOrgInfo` read in system mode, on purpose. Many users have no access to the Profile, Role or Organization objects, yet an assistant still needs to know who it is talking to and which org it is in.

- `ApexAgentGetCurrentUser` returns only the caller's own user record, such as name, email, title, profile, role and time zone, plus the name of their manager. Nothing else about any other user.
- `ApexAgentGetOrgInfo` returns org settings such as the org name, edition and time zone. No business records.

## You decide which tools are available

A tool is available only where you put it.

- An **MCP server** exposes only the tools linked to it. To make it read-only, leave `ApexAgentUpsertRecords` off.
- An **agent** uses only the tools on its topics.
- Users can chat with an agent only with the **ApexAgent User** or **ApexAgent Admin** permission set, and can connect an MCP client only with **ApexAgent User**. Only people with **ApexAgent Admin** can change the configuration or read other users' logs. See [the permission sets](/ApexAgent/start/install/#4-give-your-users-access).

See [How it's organised](/ApexAgent/project/organisation/) for the records involved.

## Signing in to the MCP server

The Endpoint URL is public, as any Salesforce Site is, but it returns nothing without a sign-in.

- A client connects through OAuth with PKCE. Each person signs in with their own Salesforce login, including your SSO and multi-factor rules.
- No client secret or password is stored in the client.
- Every call carries that user's access token and runs as that user. To cut a client off, remove the user's **ApexAgent User** permission set, or revoke their access to **ApexAgent MCP** under **Connected Apps OAuth Usage** in Setup.

### Login IP ranges

With a hosted client such as Claude or ChatGPT, tool calls reach Salesforce from that provider's servers, not from the user's own computer. So out of the box, MCP sign-ins are not held to your profiles' login IP ranges; otherwise those calls would be refused.

If you want IP restrictions enforced, edit **ApexAgent MCP** in **External Client App Manager** and change **IP Relaxation** under its OAuth policies. You then need to add the client provider's published IP ranges to the login IP ranges of the profiles that use it.

## An audit trail, kept in your org

ApexAgent keeps a record of what was done. Each user can see their own conversations and tool calls. Only people with **ApexAgent Admin** can see everyone's, along with anyone your org's own sharing settings already allow, such as a user's managers in the role hierarchy. The records are saved in your own Salesforce org, the one you installed ApexAgent in. They are not copied to the project's authors or to any outside service.

Each tool call is one record, whether it came from the agent or from an MCP client: who called it, the inputs, the output, how long it took and whether it failed. Agent conversations are saved the same way.

These are ordinary Salesforce records, so you decide who can see them, you can report on them, and you can delete them on whatever schedule your policy sets. See [Logs and dashboards](/ApexAgent/operate/logs/).

## Where your data goes

ApexAgent has no server of its own. Nothing is sent to the project's authors or to any third party it picks for you. Data leaves Salesforce only as part of answering a question, and only data that user could already see.

So it can address the user and understand "this record", the agent also tells the model who is asking (name, username, email, profile, role, language and time zone) and a few fields of the record they have open. The MCP server sends nothing of its own accord; a client gets only what a tool returns.

| | Goes to | Under |
| --- | --- | --- |
| MCP server | The client the user connected, such as Claude or ChatGPT | Your company's plan with that provider |
| Agent | The model provider you configure. OpenRouter comes preconfigured | Your account with that provider |

So the question of how long an AI provider keeps your data, and whether it trains on it, is answered by your agreement with that provider. Most companies that run Salesforce already have one.

What to check:

- **Claude or ChatGPT.** Use your company's business or enterprise plan, not personal accounts. Confirm that the plan does not train on your data, and what its retention period is. Zero data retention is available on some enterprise agreements.
- **OpenRouter.** Its privacy settings let you allow only providers that do not train on or retain prompts.
- **Your own cloud.** The agent can call any OpenAI-compatible endpoint, so you can point it at a model you already have under contract, for example through Azure or Google Vertex AI. See [Use a different provider](/ApexAgent/agent/providers/).

## For a security review

- All code is Apex in your org, and it is open source. You can read every line before you deploy it.
- No middleware, no external database, no outbound calls except to the model provider you configure for the agent.
- Access is by permission set. Tool access is by configuration.
- The audit trail stays in your org, under your control.
