# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ApexAgent is a Salesforce DX project that provides a metadata-driven framework for building AI agents inside Salesforce. Agents are configured declaratively via custom objects — selecting an LLM, assigning topics (which carry instructions and tools), and logging all execution. Tools can be backed by either Apex classes or autolaunched Flows.

**Salesforce API version:** 66.0
**Package directory:** `force-app/`

If the request is strraightforwad - dont use explore agents without needing

## Data Model Architecture

The core data model follows this hierarchy:

```
Agent__c ──MD── Topic_Map__c ──LK── Topic__c
                                      │
                              MD── Instruction__c (ordered, per-topic)
                              MD── Topic_Tool_Map__c ──LK── Tool__c
                                                              │
                                                      MD── Tool_Parameter__c
Agent__c ──LK── LLM__c
```

**Configuration objects:**
- **Agent__c** — Top-level config: links to an LLM, sets conversation depth, max tokens, reasoning effort (low/medium/high/disabled), and tool log depth
- **LLM__c** — Model registry: API name, family (Anthropic/OpenAI/Google), named credential, token costs, reasoning support flag
- **Topic__c** — Grouping of instructions and tools with an API name
- **Topic_Map__c** — Junction (MD→Agent, LK→Topic) with ordering, active flag, and quick-access config
- **Instruction__c** — Ordered prompt text per topic (MD→Topic)
- **Tool__c** — Execution type (Apex or Flow), execution name, description, and data-modification flag
- **Tool_Parameter__c** — Parameter definitions per tool (MD→Tool) with type, required flag, and optional definition class
- **Topic_Tool_Map__c** — Junction (MD→Topic, LK→Tool) with active flag

**Observability objects (logging):**
- **Thread_Log__c** — Conversation thread with UUID and timestamps
- **Message_Log__c** — Per-message: user input, agent response, model name, token counts (input/output/cached/reasoning), cost, duration, feedback
- **Tool_Log__c** — Per-tool-call: tool name, input/output, status, duration, error info (MD→Message_Log)
- **Error_Log__c** — Error + stack trace (MD→Message_Log)

**Relationships:** MD = Master-Detail, LK = Lookup. Topic_Map and Topic_Tool_Map are junction objects that enable many-to-many between Agent↔Topic and Topic↔Tool respectively.

## Permission Sets

- **ApexAgent_Admin** — Full CRUD on all ApexAgent objects
- **ApexAgent_User** — Read-only / limited access

## Skill Usage (sf-skills)

When working on Salesforce-specific tasks in this repo, use the appropriate `sf-*` skill. Key mappings:

| Task | Skill |
|------|-------|
| Apex classes, triggers, test classes | `sf-apex` |
| Custom objects, fields, validation rules, metadata XML | `sf-metadata` |
| Flows (.flow-meta.xml) | `sf-flow` |
| LWC components | `sf-lwc` |
| SOQL queries | `sf-soql` |
| Deploying metadata, scratch orgs, CI/CD | `sf-deploy` |
| Running Apex tests, coverage | `sf-testing` |
| Debug logs, governor limits | `sf-debug` |
| Permission sets, access analysis | `sf-permissions` |
| FlexiPages (.flexipage-meta.xml) | `sf-metadata` |
| Named Credentials, callouts, integrations | `sf-integration` |
| Connected Apps, OAuth | `sf-connected-apps` |
| Architecture diagrams | `sf-diagram-mermaid` |

Always prefer the specialized sf-skill over generic approaches — they enforce Salesforce-specific best practices and scoring.

## Conventions

- All custom object API names are prefixed with `ApexAgent_` and use `__c` suffix
- Metadata uses field-level `trackHistory` extensively — maintain this when adding fields
- Compact layouts are defined for every object — update them when adding important fields
- FlexiPages override the default View action on both Large and Small form factors
- Core agent framework classes (non-tool classes) must be prefixed with `ApexAgent` (e.g., `ApexAgentOrchestrator`, `ApexAgentMessageBuilder`)
- Apex classes must be organized in subfolders under `force-app/main/default/classes/` (e.g., `classes/core/`, `classes/tools/`, `classes/services/`) — never dump classes flat into the `classes/` root
- Apex code must be properly abstracted: use interfaces/abstract classes for extensibility, separate concerns (service layer, selector layer, domain layer), and avoid god classes
- If you think there are repeated utility code-  create a utility function in a utility class 
- For tools, ensure exceptions (missing input  variables, input variable no value, etc) are caught and thrown, remember that an LLM is going to call it
- For tests, test comprehensively, but keep the number of methods limited, you can do multiple assertions in a single method, consolidate the test cases into fewer methods
- When running tests, run synchronously, do not run async

## Static Analysis (mandatory after every Apex/LWC change)

After every change to Apex or LWC files, run both analyzers and fix any **Critical** or **High** severity issues before considering the work done. SLDS suggestions and complexity warnings can be ignored.

```bash
# Salesforce Code Analyzer — target only the changed file(s)
sf code-analyzer run --workspace force-app/main/default/classes/core/ApexAgentOrchestrator.cls --output-file results.html
sf code-analyzer run --workspace force-app/main/default/lwc/myComponent --output-file results.html

# PMD — target only the changed file(s)
pmd check -d force-app/main/default/classes/core/ApexAgentOrchestrator.cls -R category/apex/bestpractices.xml,category/apex/errorprone.xml,category/apex/security.xml -f text

# To check an entire subfolder (e.g., after broad refactor)
pmd check -d force-app/main/default/classes/core -R category/apex/bestpractices.xml,category/apex/errorprone.xml,category/apex/security.xml -f text
```

Scope both tools to only the files you changed — avoid running against the full `classes/` directory.

Review output for Critical/High severity violations and fix them. Ignore:
- SLDS-related suggestions
- Complexity warnings (CyclomaticComplexity, CognitiveComplexity, NcssMethodCount, etc.)
