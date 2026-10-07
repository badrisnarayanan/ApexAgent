/**
 * Assigns one permission set to one user, doing nothing if it is already
 * assigned.
 *
 * Runs as its own job because Salesforce refuses to save a permission set
 * assignment in the same transaction as ordinary records, which is what setup
 * creates. One job per assignment keeps them independent: if one fails, the
 * others still commit and the failed one shows its own error under
 * Setup > Apex Jobs.
 */
public with sharing class ApexAgentSetupPermissionQueueable implements Queueable {

    private final Id userId;
    private final String permissionSetName;

    public ApexAgentSetupPermissionQueueable(Id userId, String permissionSetName) {
        this.userId = userId;
        this.permissionSetName = permissionSetName;
    }

    // Permission sets and their assignments are setup data with no FLS to enforce.
    // Setup must be able to grant access to a user who has none yet.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    public void execute(QueueableContext context) {
        List<PermissionSet> permissionSets = [SELECT Id FROM PermissionSet WHERE Name = :permissionSetName LIMIT 1];
        if (permissionSets.isEmpty()) {
            throw new ApexAgentSetupService.SetupException(
                'Permission set ' + permissionSetName + ' was not found. Deploy the project before running setup.'
            );
        }
        Id permissionSetId = permissionSets[0].Id;

        Integer existing = [
            SELECT COUNT() FROM PermissionSetAssignment
            WHERE AssigneeId = :userId AND PermissionSetId = :permissionSetId
        ];
        if (existing == 0) {
            insert new PermissionSetAssignment(AssigneeId = userId, PermissionSetId = permissionSetId);
        }
    }
}
