---
title: Limits
description: The limits that apply to the agent, which one you might meet, and what to do about it.
---

Most agents never meet any of these. One is worth knowing about: the time Salesforce allows for an answer.

## Time to answer: 120 seconds

Each message is answered in a single Salesforce transaction, and Salesforce allows a transaction 120 seconds of waiting on outside services in total. For the agent, that is the time spent waiting for the model, plus the time to save records when it creates or updates any, added up across every step of one answer.

A typical answer takes a few seconds. You are only likely to reach 120 seconds with a slow model working through many tool steps on one question. If that happens, the user sees an error instead of an answer, and the failure is recorded in **Agent Error Logs**.

If you do see it:

- Choose a faster model. See [Use a different model](/ApexAgent/agent/models/).
- Lower **Reasoning Effort** on the Agent record. See [Customise an agent](/ApexAgent/agent/customise/).
- Ask for less in one message. Two smaller questions finish where one large one may not.

## Limits ApexAgent sets

These keep an answer from running away in time or cost.

| Limit | Value |
| --- | --- |
| Tool rounds in one answer | 10. After that the agent is told to answer with what it has gathered |
| Wait for the model, per call | 120 seconds |
| Retries when the model is busy or the connection fails | 3 |
| Length of a message a user can type | 32,000 characters |
| Rows returned by one query | 50 unless the query asks for fewer, or 200 for a grouped query |
| Conversations listed in the chat's side panel | The 50 most recent |
| Size of one logged input or output | 131,072 characters. Anything longer is cut off in the log, not in the answer |

Three more are settings on the Agent record. Lumen is set to replies of up to 10,000 tokens. Left blank, memory is 15 earlier exchanges and tool history covers the last 5 messages. See [Customise an agent](/ApexAgent/agent/customise/).

## Other Salesforce limits

These apply to any Apex code. The agent stays well inside them in normal use.

| Limit | Allowance | What uses it |
| --- | --- | --- |
| Callouts in one transaction | 100 | One per model call, counting retries, and one or two each time the agent saves records. Ten tool rounds use far fewer |
| CPU time in one transaction | 10 seconds | Time waiting for the model does not count |
| Memory in one transaction | 6 MB | Mainly the size of tool results. The 50-row default on queries keeps this small |

### API requests

Chatting with the agent does not use your org's daily API requests. The agent runs inside Salesforce, unlike an MCP client, which calls in from outside.

The one exception is saving: each time the agent creates or updates records, it uses one API request.

### Progress messages

If **Show Execution Message** is ticked on the Agent record, each tool step publishes two small platform events, one when it starts and one when it finishes. They are read inside Salesforce and held for a few minutes in a 1 MB Platform Cache partition that ApexAgent installs, so the chat can show them.

- They count toward the org's hourly event **publishing** allowance: 250,000 an hour, or 50,000 in Developer Edition. That is room for over 100,000 tool steps an hour.
- They do **not** count toward the daily event **delivery** allowance, the smaller one that platform events usually run into. That allowance covers events sent to outside subscribers, and these never leave Salesforce.

With the setting unticked, the agent publishes no events at all.

### Storage

Every conversation, message and tool call is saved as a record, so logs take up data storage over time. Delete old ones on whatever schedule suits you. See [Logs and dashboards](/ApexAgent/operate/logs/).
