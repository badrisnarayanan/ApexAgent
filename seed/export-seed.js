#!/usr/bin/env node
/**
 * Exports the ApexAgent configuration records from an org into the
 * ApexAgentSeedData static resource, which ApexAgentSetupService loads into a
 * freshly installed org.
 *
 * Usage:
 *   node seed/export-seed.js [org-alias]      (or: npm run export-seed)
 *
 * Without an alias the project's default target org is used. Review the
 * resulting git diff before committing: everything in these files ships to
 * every installer.
 *
 * Not exported, because each org generates its own values: tool schemas,
 * junction unique keys, MCP endpoint URLs, record ids and all log records.
 */
'use strict';

const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawnSync } = require('child_process');

const RESOURCE_DIR = path.join(
    __dirname, '..', 'force-app', 'main', 'default', 'staticresources', 'ApexAgentSeedData'
);
const INSTRUCTIONS_DIR = 'instructions';

const LLM_FIELDS = [
    'Name', 'Model_API_Name__c', 'Family__c', 'Named_Credential__c', 'Chat_Completions_Path__c',
    'Supports_Reasoning__c', 'Uncached_Input_Token_Cost_M__c', 'Cached_Input_Token_Cost_M__c',
    'Output_Token_Cost_M__c'
];
const TOOL_FIELDS = ['Name', 'Apex_Class_Name__c', 'Modifies_Salesforce_Data__c'];
const TOPIC_FIELDS = ['Name', 'Topic_API_Name__c', 'Description__c'];
const INSTRUCTION_FIELDS = ['Name', 'Order__c', 'Active__c'];
const AGENT_FIELDS = [
    'Name', 'Active__c', 'Description__c', 'Tagline__c', 'Avatar_Static_Resource__c', 'Primary_Color__c',
    'Has_LWC__c', 'Show_Execution_Message__c', 'Max_Tokens__c', 'Conversation_Depth__c',
    'Tool_Log_Depth__c', 'Reasoning_Effort__c'
];
const MCP_FIELDS = ['Name', 'MCP_API_Name__c', 'Description__c', 'Active__c'];

const orgAlias = process.argv[2];
if (orgAlias && !/^[\w.@-]+$/.test(orgAlias)) {
    console.error(`"${orgAlias}" is not a valid org alias or username.`);
    process.exit(1);
}

// Windows can only start the Salesforce CLI through a shell, and a shell splits
// unquoted arguments at spaces (for example a temp folder under a user name like "John Doe").
const useShell = process.platform === 'win32';
const shellArg = (arg) => (useShell ? `"${arg}"` : arg);

function query(soql) {
    // The query goes through a file so its quotes and spaces never reach a shell.
    const queryFile = path.join(os.tmpdir(), `apexagent-seed-${process.pid}.soql`);
    fs.writeFileSync(queryFile, soql);
    try {
        const args = ['data', 'query', '--file', shellArg(queryFile), '--json'];
        if (orgAlias) {
            args.push('--target-org', orgAlias);
        }
        const run = spawnSync('sf', args, {
            encoding: 'utf8',
            maxBuffer: 64 * 1024 * 1024,
            shell: useShell
        });
        if (run.error) {
            throw new Error(`Could not run the Salesforce CLI: ${run.error.message}`);
        }
        let parsed;
        try {
            parsed = JSON.parse(run.stdout);
        } catch (e) {
            throw new Error(`Unexpected Salesforce CLI output for query:\n${soql}\n${run.stdout}${run.stderr}`);
        }
        if (parsed.status !== 0) {
            throw new Error(`Query failed: ${parsed.message}\n${soql}`);
        }
        return parsed.result.records;
    } finally {
        fs.rmSync(queryFile, { force: true });
    }
}

/** Salesforce stores text typed in the UI with CRLF line endings; the repo keeps LF. */
function normalize(value) {
    return typeof value === 'string' ? value.replace(/\r\n/g, '\n') : value;
}

function pick(record, fields) {
    const picked = {};
    for (const field of fields) {
        if (record[field] !== null && record[field] !== undefined) {
            picked[field] = normalize(record[field]);
        }
    }
    return picked;
}

function slug(name) {
    return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
}

/** Setup links records by these keys, so two records sharing one cannot be told apart. */
function assertUnique(records, field, label) {
    const seen = new Set();
    for (const record of records) {
        const key = String(record[field]).toLowerCase();
        if (seen.has(key)) {
            throw new Error(
                `Two ${label} records have ${field} "${record[field]}". Rename one in the org, then export again.`
            );
        }
        seen.add(key);
    }
}

function byKey(key) {
    return (a, b) => String(a[key]).localeCompare(String(b[key]));
}

function main() {
    const llms = query(`SELECT ${LLM_FIELDS.join(', ')} FROM ApexAgent_LLM__c`);
    const tools = query(`SELECT ${TOOL_FIELDS.join(', ')} FROM ApexAgent_Tool__c`);
    const topics = query(`SELECT Id, ${TOPIC_FIELDS.join(', ')} FROM ApexAgent_Topic__c`);
    const instructions = query(
        `SELECT ${INSTRUCTION_FIELDS.join(', ')}, Instruction__c, Topic__c ` +
        'FROM ApexAgent_Instruction__c ORDER BY Order__c, Name'
    );
    const topicTools = query(
        'SELECT Topic__c, Tool__r.Apex_Class_Name__c, Active__c FROM ApexAgent_Topic_Tool_Map__c'
    );
    const agents = query(`SELECT Id, LLM__r.Name, ${AGENT_FIELDS.join(', ')} FROM ApexAgent_Agent__c`);
    const agentTopics = query(
        'SELECT Agent__c, Topic__r.Topic_API_Name__c, Order__c, Active__c ' +
        'FROM ApexAgent_Topic_Map__c ORDER BY Order__c'
    );
    const mcps = query(`SELECT Id, ${MCP_FIELDS.join(', ')} FROM ApexAgent_MCP__c`);
    const mcpTools = query(
        'SELECT MCP__c, Tool__r.Apex_Class_Name__c, Active__c FROM ApexAgent_MCP_Tool_Map__c'
    );

    assertUnique(llms, 'Name', 'LLM');
    assertUnique(agents, 'Name', 'agent');

    const instructionFiles = new Map();
    const seed = {
        llms: llms.map((llm) => pick(llm, LLM_FIELDS)).sort(byKey('Name')),
        tools: tools.map((tool) => pick(tool, TOOL_FIELDS)).sort(byKey('Apex_Class_Name__c')),
        topics: topics
            .map((topic) => ({
                ...pick(topic, TOPIC_FIELDS),
                instructions: instructions
                    .filter((instruction) => instruction.Topic__c === topic.Id)
                    .map((instruction) => {
                        const file = `${INSTRUCTIONS_DIR}/${slug(instruction.Name)}.md`;
                        if (instructionFiles.has(file)) {
                            throw new Error(
                                `Two instructions would be written to ${file}. Give them distinct names.`
                            );
                        }
                        instructionFiles.set(file, normalize(instruction.Instruction__c || ''));
                        return { ...pick(instruction, INSTRUCTION_FIELDS), file };
                    }),
                tools: topicTools
                    .filter((map) => map.Topic__c === topic.Id)
                    .map((map) => ({ tool: map.Tool__r.Apex_Class_Name__c, Active__c: map.Active__c }))
                    .sort(byKey('tool'))
            }))
            .sort(byKey('Topic_API_Name__c')),
        agents: agents
            .map((agent) => ({
                ...pick(agent, AGENT_FIELDS),
                llm: agent.LLM__r.Name,
                topics: agentTopics
                    .filter((map) => map.Agent__c === agent.Id)
                    .map((map) => ({
                        topic: map.Topic__r.Topic_API_Name__c,
                        Order__c: map.Order__c,
                        Active__c: map.Active__c
                    }))
            }))
            .sort(byKey('Name')),
        mcps: mcps
            .map((mcp) => ({
                ...pick(mcp, MCP_FIELDS),
                tools: mcpTools
                    .filter((map) => map.MCP__c === mcp.Id)
                    .map((map) => ({ tool: map.Tool__r.Apex_Class_Name__c, Active__c: map.Active__c }))
                    .sort(byKey('tool'))
            }))
            .sort(byKey('MCP_API_Name__c'))
    };

    // Instructions deleted in the org must not linger in the resource.
    fs.rmSync(path.join(RESOURCE_DIR, INSTRUCTIONS_DIR), { recursive: true, force: true });
    fs.mkdirSync(path.join(RESOURCE_DIR, INSTRUCTIONS_DIR), { recursive: true });
    for (const [file, text] of instructionFiles) {
        fs.writeFileSync(path.join(RESOURCE_DIR, file), text);
    }
    fs.writeFileSync(path.join(RESOURCE_DIR, 'data.json'), JSON.stringify(seed, null, 2) + '\n');

    console.log(
        `Exported ${seed.llms.length} LLMs, ${seed.tools.length} tools, ${seed.topics.length} topics, ` +
        `${instructionFiles.size} instructions, ${seed.agents.length} agents, ${seed.mcps.length} MCP servers ` +
        `to ${path.relative(process.cwd(), RESOURCE_DIR)}`
    );
}

try {
    main();
} catch (e) {
    console.error(e.message);
    process.exit(1);
}
