/**
 * HttpCalloutMock that routes the outbound callout from
 * ApexAgentToolExecutor.executeViaDmlBridge directly into
 * ApexAgentDmlBridgeResource.execute(), simulating a real same-org REST
 * round trip without an actual network call. Used to prove the two sides of
 * the bridge agree on the JSON contract (no double-encoding on either side).
 */
@IsTest
public class ApexAgentDmlBridgeRoundTripMock implements HttpCalloutMock {

    public HttpResponse respond(HttpRequest req) {
        RestRequest restReq = new RestRequest();
        restReq.requestBody = Blob.valueOf(req.getBody());
        RestContext.request = restReq;
        RestContext.response = new RestResponse();

        ApexAgentDmlBridgeResource.execute();

        HttpResponse res = new HttpResponse();
        res.setStatusCode(RestContext.response.statusCode != null ? RestContext.response.statusCode : 200);
        res.setBody(RestContext.response.responseBody.toString());
        return res;
    }
}
