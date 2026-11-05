/**
 * OpenAI chat completions message types for the ApexAgent framework. Responses
 * are parsed untyped by the provider adapters; these types build requests.
 */
public with sharing class ApexAgentApiTypes {

    // ─────────────────────────────────────────────────────────────────
    // Tool-call types (used in both requests and responses)
    // ─────────────────────────────────────────────────────────────────

    /** Represents a single tool call produced by the LLM. */
    public class ToolCall {
        public String id;
        public String type;
        public ToolCallFunction function;
        /**
         * Provider extras on the call that must go back unchanged, such as
         * Gemini's extra_content.google.thought_signature. Null for most providers.
         */
        public Map<String, Object> extra_content;
    }

    /** The function details within a tool call. */
    public class ToolCallFunction {
        public String name;
        /** JSON-encoded string of the function arguments as sent by the LLM. */
        public String arguments;
    }

    // ─────────────────────────────────────────────────────────────────
    // Reasoning / thinking detail types
    // Used in both responses (returned by LLM) and subsequent requests
    // (to pass encrypted thinking back for continuity).
    // ─────────────────────────────────────────────────────────────────

    /**
     * A single item in the reasoning_details array.
     * type values: "reasoning.summary" | "reasoning.encrypted" | "reasoning.text"
     */
    public class ReasoningDetail {
        public String type;
        // ReasoningDetailSummary
        public String summary;
        // ReasoningDetailEncrypted
        public String data;
        // ReasoningDetailText
        public String text;
        public String signature;
        // Shared optional
        public String format;
        public String id;
        public Integer index;
    }

    // ─────────────────────────────────────────────────────────────────
    // Message types (used when building the messages[] array)
    // ─────────────────────────────────────────────────────────────────

    /**
     * A single message in the chat completion messages array.
     * role: system / user / assistant / tool
     */
    public class ChatMessage {
        public String role;
        /** Null for assistant turns that only contain tool_calls. */
        public String content;
        /** Present only on role=assistant turns with tool invocations. */
        public List<ToolCall> tool_calls;
        /** Present only on role=tool turns (matches the ToolCall.id). */
        public String tool_call_id;
        /**
         * Passed on role=assistant turns to carry forward encrypted thinking
         * from a prior LLM response (required by some reasoning models).
         */
        public List<ReasoningDetail> reasoning_details;
    }
}
