---
title: Customise an agent
description: Change Lumen or build your own agent, with its own look, instructions, tools and model.
---

An agent is a set of records in the Setup Portal. You can reshape Lumen, or create as many agents of your own as you need, without changing code.

## What makes up an agent

- The **Agent** record: its name, look, model and settings.
- One or more **Topics**: each a bundle of instructions and tools for one area of work.
- **Instructions**: the guidance the agent is given, written in plain language.
- **Tools**: what the agent is able to do.

See [How it's organised](/ApexAgent/project/organisation/) for how these connect.

## Create an agent

1. In the Setup Portal, open **Agents** and select **New**.
2. Give it a **Name**. This is the name users see, and the name you use to place it in an app.
3. Choose its **LLM** and enter **Max Tokens**, for example 10,000. Both are required.
4. Leave **Active** ticked. An inactive agent cannot be used, which is a way to switch one off without deleting it.
5. Add at least one topic, as described below.

## Give it a look

Tick **Enable Chat Interface** on the Agent record to show the branding fields.

| Field | What it does |
| --- | --- |
| **Tagline** | A short line under the agent's name on the welcome screen |
| **Primary Color** | The agent's accent colour, used for the user's messages, the send button, the agent's name and the letter avatar. Enter a hex code such as `#2A2119`. Left blank, it is Salesforce blue |
| **Avatar Static Resource** | The API name of a static resource holding the agent's image (PNG or SVG). Left blank, the agent gets a letter avatar |

Refresh the browser page to see a change to these fields.

## Tell it what to do

### Description

The **Description** on the Agent record opens the agent's prompt: "You are *Name*. *Description*". Put the agent's role and its overall rules there. Lumen's is a good example to copy from.

### Topics

A topic groups the instructions and tools for one job, such as answering questions about records. Create a Topic record with a **Topic API Name** and a **Description** of what it covers, then link it to the agent with a **Topic Map** record.

An agent can have several topics, and a topic can be shared by several agents. The **Order** on each Topic Map sets the order the topics appear in the agent's prompt. Untick **Active** on a Topic Map to take a topic away from an agent without deleting anything.

### Instructions

Each Instruction record is one block of guidance in plain language: how to answer, what to check first, what never to do. Every active instruction in the agent's topics is sent to the model as part of its prompt.

- **Order** sets the sequence within a topic. Number them 10, 20, 30 so you can insert one later.
- Untick **Active** to try the agent without an instruction, then tick it again.

Changes take effect on the next message. There is nothing to deploy.

### Tools

Link a tool to a topic with a **Topic Tool Map** record. The agent can use only the tools on its topics, so leaving a tool off is how you stop an agent doing something. See [Built-in tools](/ApexAgent/tools/built-in/) and [Add your own tool](/ApexAgent/tools/add-a-tool/).

## Tune how it behaves

These are on the Agent record. The defaults suit most agents.

| Field | What it does | If left blank |
| --- | --- | --- |
| **LLM** | The model the agent uses. See [Use a different model](/ApexAgent/agent/models/) | Required |
| **Reasoning Effort** | How much the model thinks before it answers: low, medium, high or disabled. Higher is more accurate, slower and costs more. Use disabled for a model that does not support reasoning | The model's own default |
| **Max Tokens** | The longest reply the model may write. Lower it to cap cost | Required. Lumen is set to 10,000 |
| **Conversation Depth** | How many earlier exchanges in the conversation are sent with each new message. More gives the agent a longer memory and uses more tokens. Set it to 0 for an agent that treats every message as new | 15 |
| **Tool Log Depth** | For how many recent messages the agent also remembers the tool calls it made and their results. More helps with long multi-step work and uses more tokens | 5 |
| **Show Execution Message** | Shows the user a short progress line for each tool as it runs, such as "Searching for Northwind Traders account" | Off |

Tool Log Depth cannot be higher than Conversation Depth, and if you set Tool Log Depth you must set Conversation Depth too.

## Put it in front of users

Lumen comes ready in the ApexAgent Setup Portal's utility bar. For an agent of your own:

1. In Setup, open **App Manager** and edit the Lightning app your users work in.
2. Under **Utility Items**, add the **apexAgentChat** component. This is the chat window itself; **lumenAgent** is the same window already set to Lumen.
3. Set its **Agent Name** to the Name of your Agent record.

Users need the **ApexAgent User** permission set, the same as for Lumen.
