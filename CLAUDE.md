# CLAUDE.md

Salesforce DX project (API version 66.0, package directory `force-app/`).

If the request is straightforward, don't use explore agents unless needed.

## Skill Usage (sf-skills)

When working on Salesforce-specific tasks in this repo, use the appropriate `sf-*` skill. Key mappings:

| Task | Skill |
|------|-------|
| Apex classes, triggers, test classes | `sf-apex` |
| Custom objects, fields, validation rules, metadata XML | `sf-metadata` |
| Flows (.flow-meta.xml) | `sf-flow` |
| LWC components | `sf-lwc` + `frontend-design:frontend-design` |
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

### Metadata
- All custom object API names are prefixed with `ApexAgent_` and use the `__c` suffix
- Metadata uses field-level `trackHistory` extensively — maintain this when adding fields
- Compact layouts are defined for every object — update them when adding important fields
- FlexiPages override the default View action on both Large and Small form factors

### Apex
- Classes live under `force-app/main/default/classes/ApexAgent/`, never flat in the root:
  - `core/` — common layer shared by the agent and MCP paths: `execution/`, `schema/`, `types/`, `utils/`. In `types/`, `ApexAgentApiTypes` holds OpenAI API request/response wrappers (ToolCall etc.) and `ApexAgentExecTypes` holds internal framework execution types (ToolResult etc.)
  - `tools/` — tool implementations (shared)
  - `agent/` — agent-only code: `orchestration/`, `chat/`, `services/`, `utils/`, `types/`
  - `mcp/` — MCP-only code, with `jsonrpc/` for the JSON-RPC helpers
  - `tests/` — all test classes and test mocks, flat
  - Dependencies point one way: `agent/` and `mcp/` may use `core/` and `tools/`; `core/` never depends on `agent/` or `mcp/`, and `agent/` and `mcp/` never depend on each other. Create new subfolders freely if none fit
- Core framework classes (non-tool classes) must be prefixed with `ApexAgent` (e.g., `ApexAgentOrchestrator`, `ApexAgentMessageBuilder`)
- Apex must be properly abstracted: use interfaces/abstract classes for extensibility, separate concerns (service, selector, domain layers), and avoid god classes
- If code is repeated, put it in a utility class
- Tools are called by an LLM, so exceptions (missing input variables, input variables with no value, etc.) must be caught and thrown with clear messages

### Tests
- Test comprehensively, but keep the number of test methods limited: multiple assertions per method, consolidate cases into fewer methods
- Run tests synchronously, never async

## LWC Development

- Always invoke both `sf-lwc` and `frontend-design:frontend-design` skills when creating or editing LWC components — `sf-lwc` enforces Salesforce/PICKLES conventions, `frontend-design` ensures design quality.
- Before using any SLDS class or token, use WebFetch or WebSearch to look up the exact name from the [SLDS documentation](https://www.lightningdesignsystem.com/) — do not guess SLDS class names from memory as they change across versions.

## Static Analysis (mandatory after every Apex/LWC change)

After every change to Apex or LWC files, run both analyzers and fix any **Critical** or **High** severity issues before considering the work done. SLDS suggestions and complexity warnings can be ignored.

```bash
# Salesforce Code Analyzer — target only the changed file(s)
sf code-analyzer run --workspace force-app/main/default/classes/ApexAgent/core/execution/ApexAgentToolExecutor.cls --output-file results.html
sf code-analyzer run --workspace force-app/main/default/lwc/myComponent --output-file results.html

# PMD — target only the changed file(s)
pmd check -d force-app/main/default/classes/ApexAgent/core/execution/ApexAgentToolExecutor.cls -R category/apex/bestpractices.xml,category/apex/errorprone.xml,category/apex/security.xml -f text

# To check an entire subfolder (e.g., after broad refactor)
pmd check -d force-app/main/default/classes/ApexAgent/core -R category/apex/bestpractices.xml,category/apex/errorprone.xml,category/apex/security.xml -f text
```

Scope both tools to only the files you changed — avoid running against the full `classes/` directory.

Review output for Critical/High severity violations and fix them. Ignore:
- SLDS-related suggestions
- Complexity warnings (CyclomaticComplexity, CognitiveComplexity, NcssMethodCount, etc.)

VSCode may throw problems/errors for SObject / describe objects / variables — you can ignore them.
