trigger ApexAgentToolExecutionEventTrigger on ApexAgent_Tool_Execution__e (after insert) {
    ApexAgentExecutionMessageHandler.handleEvents(Trigger.new);
}
