/**
 * Named JSON-RPC 2.0 / MCP error codes for the MCP execution layer.
 *
 * Split into two groups, per https://modelcontextprotocol.io/specification/draft/basic#error-codes:
 *  - Standard JSON-RPC codes (-32700, -32600 to -32603) - MCP uses these as-is
 *    for general protocol failures.
 *  - ApexAgent-specific codes, for errors the MCP spec doesn't define. The
 *    spec reserves the ENTIRE -32768..-32000 band for JSON-RPC/MCP use
 *    (subdivided into -32000..-32019 "legacy", not for new allocation, and
 *    -32020..-32099 "reserved for the MCP specification" exclusively) and
 *    says application-defined codes belong outside that whole range, not
 *    just outside the -32000..-32099 slice - hence -33xxx here, not -3200x.
 */
public with sharing class ApexAgentJsonRpcErrorCodes {

    // ─── Standard JSON-RPC / MCP-sanctioned ────────────────────────────
    public static final Integer PARSE_ERROR = -32700;
    public static final Integer INVALID_REQUEST = -32600;
    public static final Integer METHOD_NOT_FOUND = -32601;
    public static final Integer INVALID_PARAMS = -32602;
    public static final Integer INTERNAL_ERROR = -32603;

    // ─── ApexAgent-specific (outside the JSON-RPC/MCP reserved range) ────
    public static final Integer AUTHORIZATION_REQUIRED = -33001;
    public static final Integer ORIGIN_NOT_ALLOWED = -33002;
    public static final Integer UNKNOWN_MCP_SERVER = -33003;
}
