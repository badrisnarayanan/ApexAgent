/**
 * Configurable HttpCalloutMock for simulating LLM chat-completion responses
 * in tests, without depending on a real Named Credential or live endpoint.
 */
@IsTest
public class ApexAgentLLMCalloutMock implements HttpCalloutMock {

    private final List<Integer> statusCodes;
    private final List<String> responseBodies;
    private final Map<String, String> headers = new Map<String, String>();
    public String lastEndpoint;
    /** Every request body sent, in order. */
    public List<String> requestBodies = new List<String>();

    /** Answers every request the same way. */
    public ApexAgentLLMCalloutMock(Integer statusCode, String responseBody) {
        this(new List<Integer>{ statusCode }, new List<String>{ responseBody });
    }

    /** Answers request n with the nth response; the last one repeats once the list runs out. */
    public ApexAgentLLMCalloutMock(List<Integer> statusCodes, List<String> responseBodies) {
        this.statusCodes = statusCodes;
        this.responseBodies = responseBodies;
    }

    public ApexAgentLLMCalloutMock withHeader(String name, String value) {
        headers.put(name, value);
        return this;
    }

    public HttpResponse respond(HttpRequest req) {
        lastEndpoint = req.getEndpoint();
        Integer index = Math.min(requestBodies.size(), statusCodes.size() - 1);
        requestBodies.add(req.getBody());
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCodes[index]);
        res.setHeader('Content-Type', 'application/json');
        for (String name : headers.keySet()) {
            res.setHeader(name, headers.get(name));
        }
        res.setBody(responseBodies[index]);
        return res;
    }

    /** The nth request body, parsed. */
    public Map<String, Object> requestBody(Integer index) {
        return (Map<String, Object>) JSON.deserializeUntyped(requestBodies[index]);
    }

    // ─────────────────────────────────────────────────────────────────
    // Canned response builders
    // ─────────────────────────────────────────────────────────────────

    public static String stopResponse(String content) {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'chatcmpl-test',
            'choices' => new List<Object>{
                new Map<String, Object>{
                    'index' => 0,
                    'finish_reason' => 'stop',
                    'message' => new Map<String, Object>{
                        'role' => 'assistant',
                        'content' => content
                    }
                }
            },
            'usage' => new Map<String, Object>{
                'prompt_tokens' => 10,
                'completion_tokens' => 5,
                'total_tokens' => 15
            }
        });
    }

    public static String lengthResponseBlankContent() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'chatcmpl-test',
            'choices' => new List<Object>{
                new Map<String, Object>{
                    'index' => 0,
                    'finish_reason' => 'length',
                    'message' => new Map<String, Object>{
                        'role' => 'assistant',
                        'content' => null
                    }
                }
            },
            'usage' => new Map<String, Object>{
                'prompt_tokens' => 10,
                'completion_tokens' => 0,
                'total_tokens' => 10
            }
        });
    }

    public static String emptyChoicesResponse() {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'chatcmpl-test',
            'choices' => new List<Object>()
        });
    }

    public static String toolCallResponse(String toolCallId, String toolName, String argumentsJson) {
        return JSON.serialize(new Map<String, Object>{
            'id' => 'chatcmpl-test',
            'choices' => new List<Object>{
                new Map<String, Object>{
                    'index' => 0,
                    'finish_reason' => 'tool_calls',
                    'message' => new Map<String, Object>{
                        'role' => 'assistant',
                        'content' => null,
                        'tool_calls' => new List<Object>{
                            new Map<String, Object>{
                                'id' => toolCallId,
                                'type' => 'function',
                                'function' => new Map<String, Object>{
                                    'name' => toolName,
                                    'arguments' => argumentsJson
                                }
                            }
                        }
                    }
                }
            },
            'usage' => new Map<String, Object>{
                'prompt_tokens' => 10,
                'completion_tokens' => 5,
                'total_tokens' => 15
            }
        });
    }
}
