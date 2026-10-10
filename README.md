# ApexAgent

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.png">
    <img src="assets/banner-light.png" alt="ApexAgent: an AI agent and an MCP server for Salesforce, built in plain Apex. No Agentforce license. No Flex Credits." width="820">
  </picture>
</p>

> 💡 **No extra Salesforce licensing.** ApexAgent uses only standard platform features: Apex, custom objects, Lightning Web Components and a Salesforce Site. It needs **no Agentforce license, no Flex Credits, no Einstein add-on and no Data Cloud**. If your org can run Apex, it can run ApexAgent.
>
> The only running cost is the AI model itself, and only for the agent: you pay your model provider directly for what you use. The MCP server costs nothing to run, because the model belongs to the client that connects.

Everything deploys into your org and runs with your users' own permissions. There is no middleware and no external server to host.

ApexAgent gives you two things. They share the same tools, and you can use either one without the other.

| | 🔌 MCP Server | 🤖 Agent |
| --- | --- | --- |
| **What it is** | An endpoint in your org that lets an outside AI client (Claude, or any MCP client) use Salesforce tools | A chat assistant inside Salesforce, in the utility bar |
| **Where the AI model runs** | In the client you connect. ApexAgent never calls a model. | Called from Apex, through OpenRouter |
| **Extra Salesforce license** | **None** | **None** |
| **Who pays for the model** | Whoever runs the client | You, through your OpenRouter key |
| **Needs an OpenRouter API key** | **No** | **Yes** |
| **Needs an External Client App (OAuth)** | **Yes** | No |
| **Users sign in with** | Their own Salesforce login, from the client | Nothing extra; they are already in Salesforce |

If you only want the MCP server, skip every step marked 🤖. If you only want the agent, skip every step marked 🔌.

## Contents

- [What's included](#whats-included)
- [Prerequisites](#prerequisites)
- [Install](#install)
- [🔌 Set up the MCP server](#-set-up-the-mcp-server)
- [🤖 Set up the agent](#-set-up-the-agent)
- [How it's organised](#how-its-organised)
- [Add your own tool](#add-your-own-tool)
- [Use a different model or provider](#use-a-different-model-or-provider)
- [Logs and dashboards](#logs-and-dashboards)
- [Troubleshooting](#troubleshooting)
- [Contributing](#contributing)
- [License](#license)

## What's included

**🧰 Ten built-in tools.** Eight are available to both the MCP server and the agent:

| Tool | What it does |
| --- | --- |
| `ApexAgentSearchObjects` | Finds objects by name or label when the exact API name isn't known |
| `ApexAgentGetObjectDetails` | Describes an object: fields, required fields, record types, child relationships |
| `ApexAgentGetFieldDetails` | Describes specific fields in depth, including picklist values and lookup targets |
| `ApexAgentGetObjectApiName` | Tells which object a record ID belongs to |
| `ApexAgentGetRecordDetails` | Reads one record by ID |
| `ApexAgentSearchRecords` | Fuzzy-searches records by name within an object |
| `ApexAgentQueryRecords` | Runs a SOQL query |
| `ApexAgentUpsertRecords` | Creates or updates records |

Two more are on the MCP server only, to give MCP clients the context they otherwise lack:

| Tool | What it does |
| --- | --- |
| `ApexAgentGetCurrentUser` | Tells the client who it is acting for: name, email, username, title, profile, role, manager, time zone and locale |
| `ApexAgentGetOrgInfo` | Gives the org's name, Id, edition and base URLs, plus a record link template so the client links records instead of showing bare IDs |

Every tool runs as the signed-in user. Object permissions, field-level security and sharing rules all apply, so nobody sees or changes anything they couldn't in the Salesforce UI. The two MCP-only tools are the one exception: they read in system mode, but only the signed-in user's own user record and the org's settings, so they still work for users with minimal permissions.

**Also included:**

- **ApexAgent Setup Portal**: a Lightning app for managing LLMs, agents, topics, instructions, tools and MCP servers.
- **Logs** of every conversation, message, tool call and error.
- **Reports and dashboards** for agent and MCP activity.
- **A setup script** that creates a working starter configuration, so there is something to use right after install.

## Prerequisites

**For everything:**

- [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli) (`sf`) and Git
- A Salesforce org where you are a System Administrator
- **Developer, Enterprise, Performance or Unlimited Edition.** The MCP server uses a Salesforce Site, which other editions do not have.
- Nothing in the org already using names that start with `ApexAgent`. A deploy overwrites components with the same name.

**🔌 Only for the MCP server:**

- An MCP client that supports remote servers with OAuth and lets you enter a client ID, such as Claude or ChatGPT

**🤖 Only for the agent:**

- An [OpenRouter](https://openrouter.ai) API key

## Install

These steps are the same whichever part you want.

**1. Get the code and sign in to your org**

```bash
git clone https://github.com/badrisnarayanan/ApexAgent.git
cd ApexAgent
sf org login web --alias my-org --set-default
```

**2. Deploy**

```bash
sf project deploy start --source-dir force-app
```

**3. Run setup**

```bash
sf apex run --file seed/setup.apex
```

Setup prints one line beginning `ApexAgent setup:` that says what it did. On a first run it:

- creates the starter configuration: 2 LLMs, 10 tools, 1 topic with 3 instructions, 1 agent (Lumen) and 1 MCP server
- assigns the **ApexAgent Admin** permission set to you
- assigns the **ApexAgent MCP Guest** permission set to the MCP Site's guest user

It is safe to run again. It never duplicates or overwrites records; a later run only finishes anything an earlier one could not.

**4. Give your users access**

Assign the **ApexAgent User** permission set to everyone who will chat with the agent or connect an MCP client.

Now continue with the part you want.

## 🔌 Set up the MCP server

[MCP](https://modelcontextprotocol.io) (Model Context Protocol) is an open standard that lets an AI client call tools hosted somewhere else. ApexAgent turns your org into an MCP server. Once a client is connected, the person using it can ask things like "what fields are on Opportunity?" or "show me my open cases", and the client calls the tools in your org to answer.

The AI model belongs to the client. ApexAgent only serves the tools, so **no OpenRouter key is needed**.

**1. Find your server URL**

Open the **ApexAgent Setup Portal** app, go to the **MCP Servers** tab and open **Default MCP Server**. Copy its **Endpoint URL**. It looks like:

```
https://<your-domain>.my.salesforce-sites.com/services/apexrest/ApexAgent/mcp/default
```

**2. Get the OAuth client ID**

In Setup, open **External Client App Manager**, open **ApexAgent MCP**, and copy the **Consumer Key** from its OAuth settings. This is the client ID your MCP client asks for. No client secret is needed: the app uses PKCE.

While you are there, edit the app and change its **Contact Email** from the placeholder `admin@example.com` to your own. It is only the contact shown for the app; sign-in works either way.

**3. Connect your client**

Add a remote MCP server in your client, with the server URL from step 1 and the client ID from step 2. When prompted, sign in with your Salesforce login. Notes for specific clients:

<details>
<summary><strong>Claude</strong></summary>

Add a custom connector with the Endpoint URL and, under the advanced settings, the client ID. Sign in with your Salesforce login when prompted.

Claude's callback URL, `https://claude.ai/api/mcp/auth_callback`, is already allowed in the External Client App.

</details>

<details>
<summary><strong>ChatGPT</strong></summary>

ChatGPT needs Developer Mode to add a custom connector. Create the connector with these settings:

| Setting | Value |
| --- | --- |
| Server URL | The Endpoint URL |
| Registration method | User-Defined OAuth Client |
| OAuth client ID | The Consumer Key |
| OAuth client secret | Leave blank |
| Token endpoint auth method | Leave empty |
| OIDC enabled | **Unticked** |

Before you connect, copy the **Callback URL** ChatGPT shows on that screen and add it to the External Client App's callback URLs in Salesforce. ChatGPT gives every connector its own callback URL, so repeat this for each new connector. Salesforce can take a few minutes to apply the change.

If sign-in fails with `invalid_scope`, ChatGPT is asking for scopes the app does not allow. Check that **OIDC enabled** is unticked.

</details>

<details>
<summary><strong>MCP Inspector</strong></summary>

Use the Endpoint URL with the client ID. Its callback URL, `http://localhost:6274/oauth/callback`, is already allowed in the External Client App.

</details>

<details>
<summary><strong>Another client</strong></summary>

The client must let you enter an OAuth client ID. Salesforce does not let clients register themselves.

1. Add the client's callback URL to the External Client App's OAuth settings.
2. Connect with the Endpoint URL and the client ID.
3. If the client requests extra scopes, limit them to `api` and `refresh_token`.

</details>

**Who can connect:** only users with the **ApexAgent User** permission set. The app is set to admin-approved users, pre-authorised through that permission set.

**More than one server:** create more MCP Server records, each with its own API name and its own set of tools. Each gets its own URL, so you can give different clients different tools.

### Limits

**Daily API requests.** Every tool call from an MCP client counts as one API request against your org's daily allowance. This is the limit that matters for normal use.

**Site page views.** The Endpoint URL goes through a Salesforce Site, and Salesforce counts page views for requests made to a Site without a valid sign-in:

- Tool calls from a signed-in user do **not** count.
- The sign-in handshake does: about two requests each time a client connects, and about one each time a user's access token expires.

Salesforce's monthly page-view allowance is 500,000 for Enterprise Edition and 1,000,000 for Unlimited and Performance. Developer Edition has no page-view limit. Because the URL is public, anyone can send it unauthenticated requests, and those count too. They cannot reach your data, but a very large flood could use up the allowance. To watch usage, open the Site under Setup > Sites and check its page-view and 24-hour usage lists.

## 🤖 Set up the agent

The agent is a chat assistant that lives in the Salesforce utility bar. The starter agent is called **Lumen**. Users ask it questions in plain language, and it uses the same tools to look things up and make changes in the org.

Here the AI model is called from Apex, so **you need an OpenRouter API key**.

**1. Add your OpenRouter key**

In Setup, go to **Named Credentials**, open the **External Credentials** tab, and open **OpenRouter Credential**. Under **Principals**, edit **Authorization** and add an authentication parameter:

- **Name:** `Authorization`
- **Value:** your OpenRouter API key

**2. Open the agent**

Open the **ApexAgent Setup Portal** app. Lumen is in the utility bar at the bottom of the screen, and also has a full-page **Lumen Agent** tab.

To put it in another Lightning app, edit that app in App Manager and add the **lumenAgent** component to its utility bar.

**3. Pick a model**

Setup creates two LLM records that both use your OpenRouter key:

| LLM | Model |
| --- | --- |
| Gemini 3.7 Flash | `google/gemini-3.7-flash` |
| Free Model Router | `openrouter/free`, which routes to models OpenRouter offers at no cost |

Open the agent record and set its **LLM** field to the one you want.

## How it's organised

Everything is configured with records, in the Setup Portal. No code change is needed to reshape an agent or an MCP server.

```
🤖 Agent ──uses──▶ LLM
   │
   └─ has ─▶ Topic ─┬─ has ─▶ Instructions   (what the agent is told)
                    └─ has ─▶ Tools          (what the agent can do)

🔌 MCP Server ─ has ─▶ Tools                 (what a client can do)
```

- **Tool**: points at an Apex class. The same tool can be given to topics and to MCP servers.
- **Topic**: a bundle of instructions and tools. An agent can have several.
- **Instruction**: a block of guidance added to the agent's prompt, in order.
- **LLM**: a model, the named credential used to reach it, and its token prices for cost tracking.

The MCP server has no instructions or topics. It exposes tools, and the connected client decides how to use them.

## Add your own tool

A tool is an Apex class with one `@InvocableMethod`. ApexAgent reads the method's labels and descriptions and builds the tool definition from them, so the descriptions are what the AI model reads to decide when and how to call your tool.

**1. Write the class**

```apex
public with sharing class ApexAgentGetAccountHealth {

    public class Input {
        @InvocableVariable(required=true label='Account Id' description='Id of the account to score.')
        public String accountId;
    }

    public class Output {
        @InvocableVariable(label='Health' description='One of: Good, At Risk, Critical.')
        public String health;
    }

    @InvocableMethod(label='Get Account Health' description='Returns a health rating for an account. Use when the user asks how an account is doing.')
    public static List<Output> run(List<Input> inputs) {
        try {
            List<Output> results = new List<Output>();
            for (Input input : inputs) {
                String accountId = ApexAgentToolInput.requireNotBlank(input.accountId, 'accountId');
                Output result = new Output();
                result.health = 'Good'; // your logic here
                results.add(result);
            }
            return results;
        } catch (Exception e) {
            ApexAgentToolErrorContext.record(e);
            throw e;
        }
    }
}
```

Conventions the built-in tools follow, and yours should too:

- **Prefix the class name with `ApexAgent`** (or your own prefix). The class name is also the tool name the model sees.
- **Throw clear errors for bad input.** The model reads the message and corrects itself. `ApexAgentToolInput` has helpers for this.
- **Wrap the method body in try/catch and call `ApexAgentToolErrorContext.record(e)`**, so the real stack trace reaches the logs.
- **Refer to other tools by class name** in descriptions, not by label.

**2. Register it**

In the Setup Portal, open the **Agent Tools** tab and create a record with **Apex Class Name** set to your class name. Tick **Modifies Salesforce Data?** if it creates, updates or deletes records.

The tool's schema is generated a few seconds after you save. If you change the class later, use the **Regenerate Schema** action on the tool record.

**3. Make it available**

From the tool's related lists, add it to an **Agent Topic** to give it to an agent, to an **MCP Server** to give it to MCP clients, or both.

## Use a different model or provider

**Another model on OpenRouter.** Nothing to set up. Create an **LLM** record with the model's OpenRouter name in **Model API Name**, and keep **Named Credential** as `OpenRouter` and **Chat Completions Path** as `/api/v1/chat/completions`. It reuses the key you already added.

**Another provider with an OpenAI-compatible API.** Create a named credential for that provider, then an LLM record that names it and gives the provider's chat completions path.

**A provider with a different API format.** The request and response handling lives in two classes:

- `ApexAgentLLMClient`: builds the request and reads the response
- `ApexAgentApiTypes`: the request and response shapes

Both follow the OpenAI chat completions format. Adapting them to another format is a contained change, and a coding agent can do it if you give it the provider's API reference and these two files.

## Logs and dashboards

The Setup Portal has tabs for:

- **Agent Thread Logs** and **Agent Message Logs**: each agent conversation and each turn in it, with token counts and cost
- **Tool Logs**: every tool call from the agent or an MCP client, with inputs, outputs, duration and status
- **Agent Error Logs**: failures, with stack traces
- **Agent Dashboard** and **MCP Dashboard**: usage, errors and slowest calls

## Troubleshooting

**Setup says "Setup did not run".** Part of the project is missing from the org. Deploy the whole `force-app` folder, then run setup again.

**Setup warns that the Site does not exist or is not active.** The agent is unaffected. For MCP, activate **ApexAgent MCP Server** under Setup > Sites, then run setup again so it can fill in the server URL and assign the guest permission set.

**The agent or an MCP client shows fewer tools than expected.** A tool with no generated schema is left out. Open the tool record and use **Regenerate Schema**, or run setup again, which retries every tool that has none.

**The agent replies with an authentication error.** The OpenRouter key is missing or wrong. Recheck step 1 of the agent setup, and confirm the user has the **ApexAgent User** permission set.

**An MCP client can't sign in.** Check that the client ID is the app's Consumer Key, that the client's callback URL is allowed in the External Client App, and that the user has the **ApexAgent User** permission set.

**Sign-in fails with `invalid_scope`.** The client asked for a scope the External Client App does not allow. Limit the scopes the client requests to `api` and `refresh_token`. In ChatGPT, untick **OIDC enabled**.

**A permission set wasn't assigned.** Setup assigns them in background jobs. Check Setup > Apex Jobs for a failed `ApexAgentSetupPermissionQueueable`.

## Contributing

**Layout**

```
force-app/main/default/
  classes/ApexAgent/
    core/      shared by the agent and the MCP server
    tools/     the built-in tools
    agent/     agent only
    mcp/       MCP server only
    setup/     the org setup run by seed/setup.apex
    tests/     all test classes
  staticresources/ApexAgentSeedData/
               the starter configuration that setup loads
seed/
  setup.apex       what installers run
  export-seed.js   regenerates the starter configuration from an org
```

**Run the tests**

```bash
sf apex run test --class-names ApexAgentToolExecutorTest --synchronous
```

**Change the starter configuration.** Edit the records in your org, then pull them into the repo:

```bash
npm run export-seed
```

This rewrites `staticresources/ApexAgentSeedData/`: `data.json` plus one markdown file per instruction. Review the diff before committing, because everything in that folder ships to every installer.

## License

[MIT](LICENSE)
