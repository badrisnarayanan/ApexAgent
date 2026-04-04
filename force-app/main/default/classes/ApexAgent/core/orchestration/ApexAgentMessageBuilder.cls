/**
 * Constructs all ChatMessage objects for an LLM request:
 * system prompt, thread history, user message, and user context message.
 */
public with sharing class ApexAgentMessageBuilder {

    private static final String GEMINI_FAMILY               = 'Google';
    private static final String DUMMY_THOUGHT_SIGNATURE     = 'skip_thought_signature_validator';
    private static final String REASONING_ENCRYPTED_TYPE    = 'reasoning.encrypted';

    // ─────────────────────────────────────────────────────────────────
    // System prompt
    // ─────────────────────────────────────────────────────────────────

    public static ApexAgentApiTypes.ChatMessage buildSystemMessage(
        ApexAgentConfigTypes.AgentConfig config,
        List<ApexAgentConfigTypes.TopicData> topics
    ) {
        String content = buildSystemContent(config, topics);
        return makeMessage('system', content);
    }

    private static String buildSystemContent(
        ApexAgentConfigTypes.AgentConfig config,
        List<ApexAgentConfigTypes.TopicData> topics
    ) {
        String agentName = String.isNotBlank(config.agentName) ? config.agentName : 'Assistant';
        String agentDesc = String.isNotBlank(config.agentDescription) ? config.agentDescription : '';

        List<String> parts = new List<String>();
        parts.add('You are ' + agentName + '. ' + agentDesc);
        parts.add('');
        parts.add('===========================================');
        parts.add('TOPICS & CAPABILITIES');
        parts.add('===========================================');

        for (ApexAgentConfigTypes.TopicData topic : topics) {
            parts.add('');
            parts.add('--- ' + topic.topicApiName + ' ---');
            if (String.isNotBlank(topic.topicDescription)) {
                parts.add('Description: ' + topic.topicDescription);
            }
            if (!topic.toolApiNames.isEmpty()) {
                parts.add('Available Tools: ' + String.join(topic.toolApiNames, ', '));
            }
            if (!topic.orderedInstructions.isEmpty()) {
                parts.add('');
                parts.add('Instructions:');
                Integer num = 1;
                for (String instr : topic.orderedInstructions) {
                    parts.add('');
                    parts.add(num + '. ' + instr);
                    parts.add('---');
                    num++;
                }
            }
        }

        return String.join(parts, '\n');
    }

    // ─────────────────────────────────────────────────────────────────
    // Thread history reconstruction
    // ─────────────────────────────────────────────────────────────────

    public static List<ApexAgentApiTypes.ChatMessage> buildThreadHistory(
        String threadUUID,
        Integer convDepth,
        Integer toolLogDepth,
        String modelFamily
    ) {
        List<ApexAgentApiTypes.ChatMessage> messages = new List<ApexAgentApiTypes.ChatMessage>();
        if (String.isBlank(threadUUID) || convDepth == null || convDepth <= 0) {
            return messages;
        }

        List<ApexAgent_Thread_Log__c> threads = [
            SELECT Id FROM ApexAgent_Thread_Log__c
            WHERE Agent_Thread_UUID__c = :threadUUID
            WITH USER_MODE
            LIMIT 1
        ];
        if (threads.isEmpty()) {
            return messages;
        }
        Id threadId = threads[0].Id;

        List<ApexAgent_Message_Log__c> pastMessages = [
            SELECT Id, User_Input__c, Agent_Response__c, Agent_Thought_Signature__c
            FROM ApexAgent_Message_Log__c
            WHERE Thread__c = :threadId
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT :convDepth
        ];
        if (pastMessages.isEmpty()) {
            return messages;
        }

        // Reverse to chronological order
        List<ApexAgent_Message_Log__c> chronological = reverseList(pastMessages);

        // Identify IDs of last toolLogDepth messages for tool log inclusion
        Set<Id> toolDepthMsgIds = new Set<Id>();
        if (toolLogDepth != null && toolLogDepth > 0) {
            Integer startIdx = Math.max(0, chronological.size() - toolLogDepth);
            for (Integer i = startIdx; i < chronological.size(); i++) {
                toolDepthMsgIds.add(chronological[i].Id);
            }
        }

        // Single query for all tool logs in scope
        Map<Id, List<ApexAgent_Tool_Log__c>> toolLogsByMsgId =
            new Map<Id, List<ApexAgent_Tool_Log__c>>();
        if (!toolDepthMsgIds.isEmpty()) {
            List<ApexAgent_Tool_Log__c> toolLogs = [
                SELECT Id, Message_Log__c, Tool_Name__c, Tool_Call_Id__c,
                       Input__c, Output__c, Agent_Thought_Signature__c
                FROM ApexAgent_Tool_Log__c
                WHERE Message_Log__c IN :toolDepthMsgIds
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ];
            for (ApexAgent_Tool_Log__c tl : toolLogs) {
                List<ApexAgent_Tool_Log__c> bucket = toolLogsByMsgId.get(tl.Message_Log__c);
                if (bucket == null) {
                    bucket = new List<ApexAgent_Tool_Log__c>();
                    toolLogsByMsgId.put(tl.Message_Log__c, bucket);
                }
                bucket.add(tl);
            }
        }

        // Build message turns
        for (ApexAgent_Message_Log__c msg : chronological) {
            // User turn
            messages.add(makeMessage('user', msg.User_Input__c));

            // Tool-call turns (only for messages within toolLogDepth)
            List<ApexAgent_Tool_Log__c> msgToolLogs = toolLogsByMsgId.get(msg.Id);
            if (toolDepthMsgIds.contains(msg.Id) && msgToolLogs != null && !msgToolLogs.isEmpty()) {
                // Assistant turn with tool_calls
                ApexAgentApiTypes.ChatMessage assistantWithTools = new ApexAgentApiTypes.ChatMessage();
                assistantWithTools.role = 'assistant';
                assistantWithTools.content = null;
                assistantWithTools.tool_calls = new List<ApexAgentApiTypes.ToolCall>();

                // Use the signature stored at tool-call time (from the intermediate LLM
                // response that triggered these tool calls), falling back to the message-level
                // signature if the tool log doesn't have one.
                String signature = msgToolLogs[0].Agent_Thought_Signature__c;
                if (String.isBlank(signature)) {
                    signature = msg.Agent_Thought_Signature__c;
                }
                if (String.isBlank(signature) && GEMINI_FAMILY.equalsIgnoreCase(modelFamily)) {
                    signature = DUMMY_THOUGHT_SIGNATURE;
                }
                if (String.isNotBlank(signature)) {
                    ApexAgentApiTypes.ReasoningDetail rd = new ApexAgentApiTypes.ReasoningDetail();
                    rd.type = REASONING_ENCRYPTED_TYPE;
                    rd.data = signature;
                    assistantWithTools.reasoning_details =
                        new List<ApexAgentApiTypes.ReasoningDetail>{ rd };
                }

                for (ApexAgent_Tool_Log__c tl : msgToolLogs) {
                    ApexAgentApiTypes.ToolCall tc = new ApexAgentApiTypes.ToolCall();
                    tc.id   = tl.Tool_Call_Id__c;
                    tc.type = 'function';
                    ApexAgentApiTypes.ToolCallFunction fn = new ApexAgentApiTypes.ToolCallFunction();
                    fn.name      = tl.Tool_Name__c;
                    fn.arguments = tl.Input__c;
                    tc.function  = fn;
                    assistantWithTools.tool_calls.add(tc);
                }
                messages.add(assistantWithTools);

                // Tool result turns
                for (ApexAgent_Tool_Log__c tl : msgToolLogs) {
                    ApexAgentApiTypes.ChatMessage toolResult = new ApexAgentApiTypes.ChatMessage();
                    toolResult.role         = 'tool';
                    toolResult.tool_call_id = tl.Tool_Call_Id__c;
                    toolResult.content      = String.isNotBlank(tl.Output__c) ? tl.Output__c : '';
                    messages.add(toolResult);
                }
            }

            // Final assistant response turn
            if (String.isNotBlank(msg.Agent_Response__c)) {
                messages.add(makeMessage('assistant', msg.Agent_Response__c));
            }
        }

        return messages;
    }

    // ─────────────────────────────────────────────────────────────────
    // User message
    // ─────────────────────────────────────────────────────────────────

    public static ApexAgentApiTypes.ChatMessage buildUserMessage(String userMessage) {
        return makeMessage('user', userMessage);
    }

    // ─────────────────────────────────────────────────────────────────
    // User context + additional context message
    // ─────────────────────────────────────────────────────────────────

    public static ApexAgentApiTypes.ChatMessage buildContextMessage(String additionalContext) {
        String profileName = '';
        String roleName    = '';

        List<Profile> profiles = [
            SELECT Name FROM Profile WHERE Id = :UserInfo.getProfileId()
            WITH USER_MODE LIMIT 1
        ];
        if (!profiles.isEmpty()) {
            profileName = profiles[0].Name;
        }

        Id userRoleId = UserInfo.getUserRoleId();
        if (userRoleId != null) {
            List<UserRole> roles = [
                SELECT Name FROM UserRole WHERE Id = :userRoleId
                WITH USER_MODE LIMIT 1
            ];
            if (!roles.isEmpty()) {
                roleName = roles[0].Name;
            }
        }

        String userTZ = UserInfo.getTimeZone().getId();
        String nowOrg  = Datetime.now().format('yyyy-MM-dd HH:mm:ss z');
        String nowUser = Datetime.now().format('yyyy-MM-dd HH:mm:ss z', userTZ);

        List<String> parts = new List<String>();
        parts.add('=== CURRENT USER CONTEXT ===');
        parts.add('User ID: ' + UserInfo.getUserId()
            + '  |  Username: ' + UserInfo.getUserName()
            + '  |  Name: ' + UserInfo.getName()
            + '  |  Email: ' + UserInfo.getUserEmail());
        parts.add('Profile ID: ' + UserInfo.getProfileId()
            + '  |  Profile Name: ' + profileName);
        parts.add('Role ID: ' + (userRoleId != null ? String.valueOf(userRoleId) : 'N/A')
            + '  |  Role Name: ' + (String.isNotBlank(roleName) ? roleName : 'N/A'));
        parts.add('Locale: ' + UserInfo.getLocale()
            + '  |  Language: ' + UserInfo.getLanguage()
            + '  |  Timezone: ' + userTZ);
        parts.add('Current Datetime (Org TZ):  ' + nowOrg);
        parts.add('Current Datetime (User TZ): ' + nowUser);

        if (String.isNotBlank(additionalContext)) {
            parts.add('');
            parts.add('=== ADDITIONAL CONTEXT ===');
            parts.add(additionalContext);
        }

        return makeMessage('system', String.join(parts, '\n'));
    }

    // ─────────────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────────────

    private static ApexAgentApiTypes.ChatMessage makeMessage(String role, String content) {
        ApexAgentApiTypes.ChatMessage msg = new ApexAgentApiTypes.ChatMessage();
        msg.role    = role;
        msg.content = content;
        return msg;
    }

    private static List<ApexAgent_Message_Log__c> reverseList(
        List<ApexAgent_Message_Log__c> items
    ) {
        List<ApexAgent_Message_Log__c> reversed = new List<ApexAgent_Message_Log__c>();
        for (Integer i = items.size() - 1; i >= 0; i--) {
            reversed.add(items[i]);
        }
        return reversed;
    }
}
