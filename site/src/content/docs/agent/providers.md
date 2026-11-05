---
title: Built-in providers
description: The four model providers that come set up, what each needs, and what ApexAgent handles for each.
---

The agent reaches AI models through **Model Provider** records. Each one is a connection: the named credential that holds the key, the API path, and the provider type, which tells ApexAgent how that provider differs from plain OpenAI. Each [LLM record](/ApexAgent/agent/models/) points at one provider.

Setup creates four providers, already wired to named credentials. To use one, you only add its key.

| Provider | Named credential | Key is sent as | Before you use it |
| --- | --- | --- | --- |
| OpenRouter | `ApexAgent_OpenRouter` | `Authorization: Bearer <key>` | Nothing |
| OpenAI | `ApexAgent_OpenAI` | `Authorization: Bearer <key>` | Nothing |
| Azure OpenAI | `ApexAgent_Azure_OpenAI` | `api-key: <key>` | Set the named credential's URL to your resource, and the LLM's **Model API Name** to your deployment name |
| Google AI Studio | `ApexAgent_Google_AI_Studio` | `Authorization: Bearer <key>` | Nothing |

To add a key, follow step 1 of [Set up the agent](/ApexAgent/agent/setup/#1-add-your-key) and pick your provider's tab. For a company AI gateway or any other OpenAI-compatible service, see [Connect a gateway](/ApexAgent/agent/gateway/). For a provider with its own format, see [Write a provider adapter](/ApexAgent/agent/adapter/).

## What ApexAgent handles for each provider

All four use the OpenAI chat completions format. Where a provider differs, ApexAgent adjusts for you:

| Provider | What ApexAgent adjusts |
| --- | --- |
| OpenAI, Azure OpenAI | Some models can't use tools and reasoning together, and models that don't reason reject the reasoning setting. If the provider rejects it, ApexAgent resends the request once with it corrected, remembers that for the model until you change its reasoning settings, and logs a warning saying which setting to change |
| OpenRouter | Uses the cost OpenRouter reports for each call instead of your token prices, including the upstream cost when you use your own provider key there (BYOK) |
| Google AI Studio | Sends Gemini's thought signature back on tool calls, which Gemini 3 requires. Counts the reasoning tokens Gemini leaves out of its token totals, so cost is right |

On every provider, ApexAgent retries a failed call up to three times when the failure is temporary: a network error, a rate limit, or a server error. An exhausted balance (`insufficient_quota`) is not retried. If the provider asks to wait more than five seconds, the call fails straight away instead of holding the user.

Warnings like the one above are saved in **Agent Error Logs** with **Severity** set to **Warning**. Users don't see them in the chat window.

## Google Vertex AI

Vertex AI isn't built in. Its OpenAI-compatible endpoint only accepts short-lived Google OAuth tokens, not API keys, and Salesforce's own OAuth credential can't complete Google's token exchange.

To use models hosted on Vertex, go through OpenRouter: add your Vertex credentials to OpenRouter as your own provider key (BYOK), and use the OpenRouter provider in ApexAgent.
