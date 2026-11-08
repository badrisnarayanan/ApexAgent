---
title: ApexAgent agent vs Agentforce
description: ApexAgent's agent next to Agentforce. What each is, what each costs and when to choose which.
---

There are two ways to put an AI agent inside Salesforce. Salesforce offers its own, called **Agentforce**, sold per user or per action. ApexAgent gives you one you deploy yourself as Apex. Both come with a ready-made agent, and both let you build your own. ApexAgent needs no Agentforce license and adds no charge of its own: you pay your AI provider for what you use, which makes it far cheaper to run.

## At a glance

| | ApexAgent agent | Agentforce |
| --- | --- | --- |
| **What it is** | A chat assistant in the utility bar, deployed as Apex | Salesforce's AI agent product suite, which covers far more than a chat assistant |
| **Salesforce license** | None needed | Flex Credits, per conversation, or a per-user add-on |
| **Model cost** | Your model provider's bill | Included in the Salesforce charge |
| **Choice of model** | Any OpenAI-compatible provider | Salesforce's model options, or bring your own |
| **Runs as the signed-in user** | Yes | Yes |
| **Ready-made agent** | Lumen, the starter agent | Salesforce's prebuilt agents |
| **Your own agents** | As many as you create, each with its own instructions, tools and model | Built in Agentforce's builder |
| **Custom actions** | Apex classes with an invocable method | Agent actions (flows, Apex, prompt templates) |
| **Instructions and topics** | Records you edit, applied from the next message | Configured in Agentforce's builder |
| **Record of every conversation** | Logs in your org | Salesforce's audit trail |
| **Data masking and toxicity checks** | Not built in. Your provider's zero data retention agreement still applies | Yes, through the Einstein Trust Layer |
| **Support** | Community, open source | Salesforce |
| **Source code** | Yours to read and change | Closed |

## What it costs

**Agentforce** is priced per action when you pay with Flex Credits. Reported pricing is $500 for 100,000 credits, with a standard action using 20 credits, so about **$0.10 per action**. A single question often takes several actions. These figures are as reported by third parties and can change; see Salesforce's [Agentforce rate card](https://www.salesforce.com/agentforce/rates/) for current prices.

**ApexAgent's agent** needs no Agentforce license, and ApexAgent adds no charge of its own. You pay your model provider for the tokens used, at their price, with nothing added per action. On Gemini 3.8 Flash, the starter model, an average question costs about **$0.016**. Your cost depends on the model you choose and how much you ask of it.

## How it works without a license

Nothing here is a workaround. The agent is built from features your org already has:

- **Apex** runs the agent and its tools.
- **A named credential** calls the model provider you choose.
- **Custom objects** hold the agent's configuration and its logs.
- **A Lightning web component** is the chat window.

What Salesforce charges for with Agentforce is its own model access and the services around it. ApexAgent leaves the model to you, and adds no charge of its own.

## A worked example

ApexAgent's figures are an average question in our own test org, priced at Gemini 3.8 Flash rates ($0.75 per million input tokens, $0.075 cached, $3.75 output). Agentforce's come from Salesforce's [Flex Credits rate card](https://www.salesforce.com/agentforce/rates/).

| | ApexAgent | Agentforce |
| --- | --- | --- |
| One average question (1.7 tool calls) | $0.016 | $0.17 |
| One question that uses 3 tools | about $0.02 | $0.30 |
| 100 people, 20 questions each working day, for a month (22 days) | about $720 | about $7,500 |

That is about **10 times less** per question.

How the Agentforce column is worked out: Salesforce's rate card charges 20 Flex Credits for each agent action, and Flex Credits are reported at $0.005 each. We count each tool call as one action, so 1.7 actions is 34 credits, or $0.17.

Two things to keep in mind:

- **The model matters.** Our figures are on a low-cost model. An average question sends about 30,000 tokens to the model, so on a premium model priced near $3 per million input tokens the same question costs about $0.10. That is still less than Agentforce, but nearer 2 times less than 10.
- **Counting actions.** We assume one tool call is one Agentforce action. Salesforce may count a multi-step question differently, and it sells other pricing models too, such as per conversation and per user.

## When to choose which

The main reason to choose ApexAgent is cost. Both can use a model you bring, and both run as the signed-in user.

Choose **ApexAgent's agent** if:

- You want an assistant inside Salesforce at a fraction of the cost of an Agentforce license or Flex Credits
- Your AI provider or gateway already gives you zero data retention, and that is the protection you need
- You want instructions, tools and logs you control as ordinary records
- You want code you can read, audit and adapt

Choose **Agentforce** if you need:

- The wider suite, not only a chat assistant: ready-made agents for sales, service and other clouds, and the tooling around them
- The Einstein Trust Layer's data masking and toxicity checks, on top of zero data retention. See [Security and data](/ApexAgent/operate/security/#compared-with-the-einstein-trust-layer)
- A vendor to call when something breaks

The two are not exclusive. ApexAgent runs alongside Agentforce in the same org.
