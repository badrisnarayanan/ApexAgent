/**
 * Checks an org is ready before ApexAgentSetupService creates anything in it.
 *
 * Blockers stop setup: without them the starter records would be created but
 * left unusable. Warnings do not: they describe an optional part (the MCP
 * Site) that a later setup run can finish.
 *
 * The custom objects are not checked. The setup classes reference them, so
 * these classes cannot be deployed to an org where the objects are missing.
 */
public with sharing class ApexAgentSetupPreflight {

    public class Report {
        public List<String> blockers = new List<String>();
        public List<String> warnings = new List<String>();
        /** The MCP Site's guest user, or null when the Site or its guest user does not exist. */
        public Id guestUserId;
        public Boolean isSiteActive = false;
    }

    public static Report check() {
        Report report = new Report();
        checkPermissionSets(report);
        checkSite(report);
        return report;
    }

    // Permission sets are setup metadata with no CRUD or FLS to enforce.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static void checkPermissionSets(Report report) {
        Set<String> missing = new Set<String>{
            ApexAgentSetupService.ADMIN_PERMISSION_SET, ApexAgentSetupService.GUEST_PERMISSION_SET
        };
        for (PermissionSet permissionSet : [SELECT Name FROM PermissionSet WHERE Name IN :missing]) {
            missing.remove(permissionSet.Name);
        }
        if (!missing.isEmpty()) {
            report.blockers.add(
                'Permission set(s) ' + String.join(new List<String>(missing), ', ')
                + ' are not in this org. Deploy the whole force-app folder.'
            );
        }
    }

    // Site is setup metadata with no CRUD or FLS to enforce.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static void checkSite(Report report) {
        String siteName = ApexAgentMcpTriggerHandler.MCP_SITE_NAME;
        List<Site> sites = [SELECT GuestUserId, Status, SiteType FROM Site WHERE Name = :siteName LIMIT 1];
        String consequence = ' MCP clients cannot connect until this is fixed and setup is run again; the chat agent is not affected.';

        if (sites.isEmpty()) {
            report.warnings.add('Site ' + siteName + ' does not exist. Deploy the whole force-app folder.' + consequence);
            return;
        }
        Site site = sites[0];
        report.guestUserId = site.GuestUserId;
        // The same definition of a usable Site that ApexAgentMcpTriggerHandler applies.
        report.isSiteActive = site.Status == 'Active' && site.SiteType == 'Visualforce';

        if (!report.isSiteActive) {
            report.warnings.add('Site ' + siteName + ' exists but is not active. Activate it in Setup > Sites.' + consequence);
        }
        if (site.GuestUserId == null) {
            report.warnings.add('Site ' + siteName + ' has no guest user, so the guest permission set cannot be assigned.' + consequence);
        }
    }
}
