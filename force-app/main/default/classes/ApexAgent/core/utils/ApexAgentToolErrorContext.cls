/**
 * Carries a tool's own stack trace across the Invocable.Action boundary.
 *
 * Tools run through Invocable.Action.invoke(), which catches anything the tool throws and
 * returns only an error message — the exception object and its stack trace are lost. Each
 * tool's @InvocableMethod therefore records the exception here before rethrowing, and
 * ApexAgentToolExecutor reads it back once invoke() returns.
 */
public with sharing class ApexAgentToolErrorContext {

    private static String capturedStackTrace;

    /** Clears any trace left by a previous tool call in the same transaction. */
    public static void reset() {
        capturedStackTrace = null;
    }

    /** Records where the tool threw. Call from the tool's catch block, then rethrow. */
    public static void record(Exception e) {
        capturedStackTrace = e.getStackTraceString();
    }

    /** Returns the recorded trace (null if the tool recorded none) and clears it. */
    public static String consume() {
        String trace = capturedStackTrace;
        capturedStackTrace = null;
        return trace;
    }
}
