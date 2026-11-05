---
title: Change the model
description: Switch the agent to another model, and set the model's prices for cost tracking.
---

Each model the agent can use is an **LLM** record in the Setup Portal. An agent uses the one named in its **LLM** field, so changing model is two steps: create the LLM record if it does not exist, then pick it on the agent.

Setup creates five to start with: Gemini 3.8 Flash and a free model router on [OpenRouter](https://openrouter.ai), Gemini 3.8 Flash on Google AI Studio, GPT-5 Mini on Azure OpenAI and GPT-5.4 Nano on OpenAI.

## Add a model

In the Setup Portal, open **LLMs** and select **New**.

| Field | What to enter |
| --- | --- |
| **Model API Name** | The model's name exactly as the provider gives it. On OpenRouter, for example, `google/gemini-3.8-flash`. On Azure OpenAI, your deployment name |
| **Model Provider** | The connection to use, for example **OpenRouter**. [Built-in providers](/ApexAgent/agent/providers/) lists the four that come set up |
| **Supports Reasoning?** | Tick if the model can reason before answering. When it's unticked, no reasoning setting is sent, because models that don't reason reject it |
| **Token costs** | The provider's prices per million tokens for input, cached input and output. Tokens are the units models count text in; 1,000 is roughly 750 words. These drive the cost figures in the logs and dashboard. On OpenRouter, the cost OpenRouter reports is used instead |

A new model on a provider you already use needs nothing else. It reuses that provider's key.

## Switch an agent to it

Open the Agent record and set **LLM** to the new record. The next message uses it.

Two settings on the Agent record depend on the model, so check them when you switch:

- **Reasoning Effort**: set it to **disabled** for a model that does not support reasoning.
- **Max Tokens**: the longest reply the model may write.

See [Customise an agent](/ApexAgent/agent/customise/) for what each does.

## A model from another provider

OpenAI, Azure OpenAI and Google AI Studio come set up and only need their key; see [Set up the agent](/ApexAgent/agent/setup/#1-add-your-key). For your company's AI gateway or any other service, [connect a gateway](/ApexAgent/agent/gateway/) first.
