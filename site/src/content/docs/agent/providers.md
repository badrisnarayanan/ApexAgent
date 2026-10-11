---
title: Use a different provider
description: The agent works with any OpenAI-compatible provider. Connect OpenAI, Azure OpenAI, your company's AI gateway or another service.
---

The agent talks to AI models in the OpenAI chat completions format, the format most providers and AI gateways accept. ApexAgent comes with a connection to [OpenRouter](https://openrouter.ai) already set up, so you can start with one key. You can switch to your own provider at any time.

To change model without changing provider, see [Use a different model](/ApexAgent/agent/models/).

## Which providers work

| Provider | Status |
| --- | --- |
| OpenRouter | Preconfigured and tested |
| OpenAI, Azure OpenAI | Use the same format. Follow [Connect your own provider](#connect-your-own-provider) |
| A company AI gateway, or another OpenAI-compatible service | Follow the same steps |
| Google Vertex AI | Not tested by us. Uses the same format, but signs in with a short-lived token instead of a fixed key, so its credential in Salesforce is set up for OAuth rather than a pasted key |
| Google Gemini, directly | Has an OpenAI-compatible endpoint. Not tested by us; if a field differs, it is the same small code change as below |
| A provider with its own format | A small code change. See [A provider with a different format](#a-provider-with-a-different-format) |

OpenRouter is the one we test. Other OpenAI-compatible providers should work the same way for chat, tool calls, token counts, cost tracking and logs; [What to check on a new provider](#what-to-check-on-a-new-provider) lists what is most likely to differ.

## Connect your own provider

You need the provider's base URL, its chat completions path, and an API key. Three examples:

| Provider | URL | Chat Completions Path | Key is sent as |
| --- | --- | --- | --- |
| OpenAI | `https://api.openai.com` | `/v1/chat/completions` | `Authorization: Bearer <key>` |
| Azure OpenAI | `https://<your-resource>.openai.azure.com` | `/openai/v1/chat/completions` | `api-key: <key>` |
| OpenRouter | `https://openrouter.ai` | `/api/v1/chat/completions` | `Authorization: Bearer <key>` |

### 1. Store the key

In Setup, open **Named Credentials** and go to the **External Credentials** tab. Select **New**.

- **Label** and **Name**: for example `My Provider Credential`
- **Authentication Protocol**: **Custom**

Save it. Under **Principals**, select **New**, name the principal, and add an authentication parameter:

- **Name**: `ApiKey`
- **Value**: your API key

Under **Custom Headers**, select **New** and add the header your provider expects. Use the names you chose above in place of `My_Provider_Credential`:

- For `Authorization: Bearer <key>`: name `Authorization`, value `{!'Bearer ' & $Credential.My_Provider_Credential.ApiKey}`
- For `api-key: <key>`: name `api-key`, value `{!$Credential.My_Provider_Credential.ApiKey}`

### 2. Create the named credential

On the **Named Credentials** tab, select **New**.

- **Label** and **Name**: for example `MyProvider`. You enter this name on the LLM record
- **URL**: the provider's base URL
- **External Credential**: the one you just created
- Turn on **Allow Formulas in HTTP Header**, and turn off **Generate Authorization Header**

### 3. Let your users use it

Open the **ApexAgent User** permission set, go to **External Credential Principal Access**, and add the principal you created. Do the same on **ApexAgent Admin**. Without this, the agent fails with a credential error for that user.

### 4. Create the LLM record

In the Setup Portal, open **LLMs** and select **New**. [Use a different model](/ApexAgent/agent/models/) explains every field.

| Field | What to enter |
| --- | --- |
| **Model API Name** | The model's name exactly as the provider gives it. On Azure, your deployment name |
| **Named Credential** | The name from step 2 |
| **Chat Completions Path** | The provider's path, from the table above |
| **Family** | The model's maker, such as OpenAI, Anthropic or Google |
| **Supports Reasoning?** | Tick if the model can reason before answering |
| **Token costs** | The provider's prices per million tokens. These drive the cost figures in the logs and dashboard |

### 5. Use it

Open your Agent record, set **LLM** to the new record, and send a message.

If it fails, open **Agent Error Logs**. The provider's own error message is saved there, and it usually names the setting it did not accept.

## What to check on a new provider

Two settings on the Agent record depend on the model, on any provider:

- **Reasoning Effort** is sent as `reasoning_effort`. Set it to **disabled** for a model that does not support reasoning.
- **Max Tokens** is sent as `max_completion_tokens`.

The logs keep the reasoning token count for every provider that reports it. The model's reasoning text itself is not saved.

## A provider with a different format

If your provider or gateway does not use the OpenAI format, or names a field differently, the change is small and stays in two classes:

- `ApexAgentLLMClient`: builds the request and reads the response
- `ApexAgentApiTypes`: the request and response shapes

Give those two files and your provider's API reference to a coding agent and ask it to adapt them. Nothing else in ApexAgent needs to change: tools, logs, the chat window and the MCP server are unaffected.
