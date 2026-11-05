---
title: Write a provider adapter
description: Support a model provider with its own request or response format by writing one Apex class.
---

If a service names a field differently, or doesn't use the OpenAI format at all, write your own adapter. It's one Apex class, and you connect it the same way as a [gateway](/ApexAgent/agent/gateway/): a named credential for the key, then a Model Provider record that names your class.

## Write the class

1. Create a class that extends `ApexAgentLLMProvider` and has a public no-argument constructor.
2. Override only the methods where your provider differs. The base class already does plain OpenAI, so a small difference is a small class:
   - `endpoint`: the URL to call
   - `buildRequestBody`, `mapReasoningEffort`: the request
   - `retryBodyAfterRejection`, `isRetryable`: what to do when a call fails
   - `parseResponse`, `parseUsage`, `readThought`: the reply, token counts and cost
   - `readContinuityToken`, `attachContinuity`: anything the provider needs sent back on the next call of the same turn
3. Create a Model Provider record as in [Connect a gateway](/ApexAgent/agent/gateway/#4-create-the-model-provider-record), with **Provider Type** set to **Custom** and **Apex Class** set to your class name.

`ApexAgentOpenRouterProvider` and `ApexAgentGeminiProvider` are short working examples. Give one of them, `ApexAgentLLMProvider` and your provider's API reference to a coding agent and ask it to write the adapter. Nothing else in ApexAgent needs to change: tools, logs, the chat window and the MCP server are unaffected.

If the class is missing or doesn't extend `ApexAgentLLMProvider`, the agent fails with an error naming the provider record and the class.
