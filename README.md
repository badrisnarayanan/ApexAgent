# ApexAgent

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/banner-dark.png">
    <img src="assets/banner-light.png" alt="ApexAgent: an AI agent and an MCP server for Salesforce, built in plain Apex. No Agentforce license. No Flex Credits." width="820">
  </picture>
</p>

**[Documentation](https://badrisnarayanan.github.io/ApexAgent/)** · [Install](https://badrisnarayanan.github.io/ApexAgent/start/install/) · [MCP server](https://badrisnarayanan.github.io/ApexAgent/mcp/setup/) · [Agent](https://badrisnarayanan.github.io/ApexAgent/agent/setup/) · [Tools](https://badrisnarayanan.github.io/ApexAgent/tools/built-in/)

> 💡 **No extra Salesforce licensing.** ApexAgent uses only standard platform features: Apex, custom objects, Lightning Web Components and a Salesforce Site. It needs **no Agentforce license, no Flex Credits, no Einstein add-on and no Data Cloud**. It runs in Developer, Enterprise, Performance and Unlimited Edition orgs.
>
> The only running cost is the AI model itself, and only for the agent: you pay your model provider directly for what you use. The MCP server costs nothing to run, because the model belongs to the client that connects.

Everything deploys into your org and runs with your users' own permissions. There is no middleware and no external server to host.

ApexAgent gives you two things. They share the same tools, and you can use either one without the other.

| | 🔌 MCP Server | 🤖 Agent |
| --- | --- | --- |
| **What it is** | An endpoint in your org that lets an outside AI client (Claude, ChatGPT, or any MCP client) use Salesforce tools | A chat assistant inside Salesforce, in the utility bar |
| **Where the AI model runs** | In the client you connect. ApexAgent never calls a model. | Called from Apex, through OpenRouter |
| **Extra Salesforce license** | **None** | **None** |
| **Who pays for the model** | Whoever runs the client | You, through your OpenRouter key |
| **Needs an OpenRouter API key** | **No** | **Yes** |
| **Needs an External Client App (OAuth)** | **Yes** | No |
| **Users sign in with** | Their own Salesforce login, from the client | Nothing extra; they are already in Salesforce |

## Quick start

You need the [Salesforce CLI](https://developer.salesforce.com/tools/salesforcecli), Git, and an org where you are a System Administrator. See the full [prerequisites](https://badrisnarayanan.github.io/ApexAgent/start/prerequisites/).

```bash
git clone https://github.com/badrisnarayanan/ApexAgent.git
cd ApexAgent
sf org login web --alias my-org --set-default
sf project deploy start --source-dir force-app
sf apex run --file seed/setup.apex
```

Setup creates a starter configuration: 2 LLMs, 10 tools, 1 agent (Lumen) and 1 MCP server. Then follow the [install guide](https://badrisnarayanan.github.io/ApexAgent/start/install/) to give your users access and finish the part you want:

- 🔌 [Set up the MCP server](https://badrisnarayanan.github.io/ApexAgent/mcp/setup/) and [connect a client](https://badrisnarayanan.github.io/ApexAgent/mcp/clients/) such as Claude or ChatGPT
- 🤖 [Set up the agent](https://badrisnarayanan.github.io/ApexAgent/agent/setup/)

## What's included

- **[Ten built-in tools](https://badrisnarayanan.github.io/ApexAgent/tools/built-in/)** for finding objects, reading and searching records, running SOQL queries and saving changes. Every tool that touches records runs as the signed-in user.
- **ApexAgent Setup Portal**: a Lightning app for managing LLMs, agents, topics, instructions, tools and MCP servers.
- **Logs** of every conversation, message, tool call and error, with [reports and dashboards](https://badrisnarayanan.github.io/ApexAgent/operate/logs/).
- **A setup script** that creates a working starter configuration.

## Documentation

| | |
| --- | --- |
| [Add your own tool](https://badrisnarayanan.github.io/ApexAgent/tools/add-a-tool/) | Write one Apex class and give it to an agent, an MCP server, or both |
| [Use a different model](https://badrisnarayanan.github.io/ApexAgent/agent/models/) | Another OpenRouter model or another provider |
| [MCP limits](https://badrisnarayanan.github.io/ApexAgent/mcp/limits/) | The Salesforce limits that apply, and how to watch them |
| [How it's organised](https://badrisnarayanan.github.io/ApexAgent/project/organisation/) | The records that make up an agent and an MCP server |
| [Troubleshooting](https://badrisnarayanan.github.io/ApexAgent/operate/troubleshooting/) | Fixes for common setup and sign-in problems |
| [Contributing](https://badrisnarayanan.github.io/ApexAgent/project/contributing/) | Repository layout, tests, and the starter configuration |

The documentation site's source is in [`site/`](site/).

## License

[MIT](LICENSE)
