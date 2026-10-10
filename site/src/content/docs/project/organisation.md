---
title: How it's organised
description: The records that make up an agent and an MCP server, and how they relate.
---

Everything is configured with records, in the Setup Portal. No code change is needed to reshape an agent or an MCP server.

```
Agent --uses--> LLM
  |
  +-- has --> Topic --+-- has --> Instructions   (what the agent is told)
                      +-- has --> Tools          (what the agent can do)

MCP Server -- has --> Tools                      (what a client can do)
```

- **Tool**: points at an Apex class. The same tool can be given to topics and to MCP servers.
- **Topic**: a bundle of instructions and tools. An agent can have several.
- **Instruction**: a block of guidance added to the agent's prompt, in order.
- **LLM**: a model, the named credential used to reach it, and its token prices for cost tracking.

The MCP server has no instructions or topics. It exposes tools, and the connected client decides how to use them.
