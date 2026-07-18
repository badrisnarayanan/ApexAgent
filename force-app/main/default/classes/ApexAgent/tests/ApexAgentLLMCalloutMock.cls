/**
 * Configurable HttpCalloutMock for simulating LLM chat-completion responses
 * in tests, without depending on a real Named Credential or live endpoint.
 */
@IsTest
public class ApexAgentLLMCalloutMock implements HttpCalloutMock {

    private final Integer statusCode;
    private final String responseBody;

    public ApexAgentLLMCalloutMock(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setHeader('Content-Type', 'application/json');
        res.setBody(responseBody);
        return res;
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
