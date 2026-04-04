/**
 * OpenAI / OpenRouter API request and response wrapper types for the ApexAgent framework.
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

    // ─────────────────────────────────────────────────────────────────
    // Response types
    // ─────────────────────────────────────────────────────────────────

    /** Top-level chat completion response from OpenRouter. */
    public class ChatCompletionResponse {
        public String id;
        public List<Choice> choices;
        public Usage usage;
    }

    /** A single choice in the response choices array. */
    public class Choice {
        public Integer index;
        public ResponseMessage message;
        /** stop / tool_calls / length / content_filter / error */
        public String finish_reason;
    }

    /** The assistant message returned inside a Choice. */
    public class ResponseMessage {
        public String role;
        public String content;
        public List<ToolCall> tool_calls;
        /** Direct reasoning string (nullable); present when model returns a flat thought. */
        public String reasoning;
        /** Structured reasoning details array; present for extended-thinking models. */
        public List<ReasoningDetail> reasoning_details;
    }

    // ─────────────────────────────────────────────────────────────────
    // Usage types (per OpenRouter spec)
    // ─────────────────────────────────────────────────────────────────

    public class Usage {
        public Integer prompt_tokens;
        public Integer completion_tokens;
        public Integer total_tokens;
        public PromptTokensDetails prompt_tokens_details;
        public CompletionTokensDetails completion_tokens_details;
    }

    public class PromptTokensDetails {
        public Integer cached_tokens;
        public Integer cache_write_tokens;
    }

    public class CompletionTokensDetails {
        public Integer reasoning_tokens;
    }
}
