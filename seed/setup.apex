// One-time setup for a newly installed org. Run after deploying the project and
// adding the Remote Site Setting for your org's own domain:
//
//     sf apex run --file seed/setup.apex
//
// Checks the org is ready, creates the starter LLMs, tools, topics, instructions,
// agent and MCP server, and assigns the ApexAgent permission sets. Read the
// message it prints: it says what was done and anything left for you to fix.
//
// Safe to run again. It never duplicates or overwrites existing records, and a
// later run finishes whatever an earlier one could not.
System.debug(LoggingLevel.ERROR, 'ApexAgent setup: ' + ApexAgentSetupService.run().message);
