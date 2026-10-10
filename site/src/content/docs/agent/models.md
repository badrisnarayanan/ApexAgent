---
title: Use a different model
description: Point the agent at another OpenRouter model, another provider, or a provider with a different API format.
---

## Another model on OpenRouter

Nothing to set up. Create an **LLM** record with the model's OpenRouter name in **Model API Name**, and keep **Named Credential** as `OpenRouter` and **Chat Completions Path** as `/api/v1/chat/completions`. It reuses the key you already added.

## Another provider with an OpenAI-compatible API

Create a named credential for that provider, then an LLM record that names it and gives the provider's chat completions path.

## A provider with a different API format

The request and response handling lives in two classes:

- `ApexAgentLLMClient`: builds the request and reads the response
- `ApexAgentApiTypes`: the request and response shapes

Both follow the OpenAI chat completions format. Adapting them to another format is a contained change, and a coding agent can do it if you give it the provider's API reference and these two files.
