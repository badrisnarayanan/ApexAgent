---
title: Use a different model
description: Switch the agent to another model, and set the model's prices for cost tracking.
---

Each model the agent can use is an **LLM** record in the Setup Portal. An agent uses the one named in its **LLM** field, so changing model is two steps: create the LLM record if it does not exist, then pick it on the agent.

Setup creates two to start with, Gemini 3.7 Flash and a free model router, both on [OpenRouter](https://openrouter.ai).

## Add a model

In the Setup Portal, open **LLMs** and select **New**.

| Field | What to enter |
| --- | --- |
| **Model API Name** | The model's name exactly as the provider gives it. On OpenRouter, for example, `google/gemini-3.7-flash` |
| **Named Credential** | The connection to the provider. For the preconfigured one, `OpenRouter` |
| **Chat Completions Path** | The provider's path. For OpenRouter, `/api/v1/chat/completions` |
| **Family** | The model's maker, such as OpenAI, Anthropic or Google |
| **Supports Reasoning?** | Tick if the model can reason before answering |
| **Token costs** | The provider's prices per million tokens for input, cached input and output. Tokens are the units models count text in; 1,000 is roughly 750 words. These drive the cost figures in the logs and dashboard |

A new model on the provider you already use needs nothing else. It reuses the key you added.

## Switch an agent to it

Open the Agent record and set **LLM** to the new record. The next message uses it.

Two settings on the Agent record depend on the model, so check them when you switch:

- **Reasoning Effort**: set it to **disabled** for a model that does not support reasoning.
- **Max Tokens**: the longest reply the model may write.

See [Customise an agent](/ApexAgent/agent/customise/) for what each does.

## A model from another provider

To use a model from OpenAI, Azure OpenAI, your company's AI gateway or anywhere else, connect that provider first. See [Use a different provider](/ApexAgent/agent/providers/).
