/**
 * Path parsing shared by the MCP endpoint and its protected resource metadata
 * endpoint. String-only, no SOQL - both run in the guest branch too.
 */
public with sharing class ApexAgentMcpPathUtils {

    private static final String SERVER_NAME_PATTERN = '[A-Za-z0-9_-]+';

    /**
     * Pulls the server name segment following pathMarker out of the raw request
     * URI, or null if it's absent or not a valid API name. The accepted charset
     * is the same one MCP_API_Name__c enforces, so nothing that could never
     * match a record (or break out of the quoted WWW-Authenticate value the
     * guest branch builds from this) gets through.
     */
    public static String extractServerName(String requestUri, String pathMarker) {
        Integer markerIndex = requestUri.indexOf(pathMarker);
        if (markerIndex == -1) {
            return null;
        }
        String remainder = requestUri.substring(markerIndex + pathMarker.length());
        Integer slashIndex = remainder.indexOf('/');
        String name = slashIndex == -1 ? remainder : remainder.substring(0, slashIndex);
        return Pattern.matches(SERVER_NAME_PATTERN, name) ? name : null;
    }
}
