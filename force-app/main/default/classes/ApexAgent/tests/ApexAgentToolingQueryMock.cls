/**
 * HttpCalloutMock for the Tooling API self-callout ApexAgentSymbolTableService
 * makes to bulk-resolve SymbolTables. Returns a fixed status/body regardless of
 * the requested query, so tests fully control the crafted SymbolTable/Body pair
 * they want the resolver to parse.
 */
@IsTest
public class ApexAgentToolingQueryMock implements HttpCalloutMock {

    private final Integer statusCode;
    private final String responseBody;

    public ApexAgentToolingQueryMock(Integer statusCode, String responseBody) {
        this.statusCode = statusCode;
        this.responseBody = responseBody;
    }

    public HttpResponse respond(HttpRequest req) {
        HttpResponse res = new HttpResponse();
        res.setStatusCode(statusCode);
        res.setBody(responseBody);
        return res;
    }
}
