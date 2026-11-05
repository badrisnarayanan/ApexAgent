---
title: Connect a gateway
description: Connect the agent to your company's AI gateway or any other service that accepts the OpenAI chat completions format.
---

For a company AI gateway or any other service that accepts the OpenAI chat completions format, you need its base URL, its chat completions path, and an API key.

## 1. Store the key

In Setup, open **Named Credentials** and go to the **External Credentials** tab. Select **New**.

- **Label** and **Name**: for example `My Gateway Credential`
- **Authentication Protocol**: **Custom**

Save it. Under **Principals**, select **New**, name the principal `Authorization`, and add an authentication parameter:

- **Name**: `Authorization`
- **Value**: your API key

Under **Custom Headers**, select **New** and add the header your service expects. Use the names you chose above in place of `My_Gateway_Credential`:

- For `Authorization: Bearer <key>`: name `Authorization`, value `{!'Bearer ' & $Credential.My_Gateway_Credential.Authorization}`
- For `api-key: <key>`: name `api-key`, value `{!$Credential.My_Gateway_Credential.Authorization}`

## 2. Create the named credential

On the **Named Credentials** tab, select **New**.

- **Label** and **Name**: for example `My_Gateway`
- **URL**: the service's base URL
- **External Credential**: the one you just created
- Turn on **Allow Formulas in HTTP Header**, and turn off **Generate Authorization Header**

## 3. Let your users use it

Open the **ApexAgent User** permission set, go to **External Credential Principal Access**, and add the principal you created. Do the same on **ApexAgent Admin**. Without this, the agent fails with a credential error for that user.

## 4. Create the Model Provider record

In the Setup Portal, open **Model Providers** and select **New**.

| Field | What to enter |
| --- | --- |
| **Provider Name** | A name people will recognise, for example `My Gateway` |
| **Provider Type** | **OpenAI** for any service that speaks the plain OpenAI format. Pick **OpenRouter** or **Google AI Studio** only if the service passes those providers' responses through unchanged. If the service uses a format of its own, see [Write a provider adapter](/ApexAgent/agent/adapter/) |
| **Named Credential** | The name from step 2 |
| **Chat Completions Path** | The path after the base URL, for example `/v1/chat/completions`. Leave it blank if the named credential's URL already ends at the endpoint |

## 5. Add an LLM and use it

Create an LLM record that points at the new provider, as in [Change the model](/ApexAgent/agent/models/#add-a-model), then set it on your agent and send a message.

If it fails, open **Agent Error Logs**. The provider's own error message is saved there, and it usually names the setting it did not accept.
