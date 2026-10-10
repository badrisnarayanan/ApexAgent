/**
 * Apex Action tool: returns details of the user the tool runs as.
 *
 * An MCP client only holds an OAuth token, so it has no idea who it is acting for.
 * This gives it the person's identity, role, manager and locale so it can resolve
 * "my", "me" and "my team" requests and address the user correctly.
 */
public with sharing class ApexAgentGetCurrentUser {

    public class Output {
        @InvocableVariable(label='User Id' description='Id of the current user. Use it to filter records by OwnerId, CreatedById and similar fields.')
        public Id userId;

        @InvocableVariable(label='Name' description='Full name of the current user.')
        public String name;

        @InvocableVariable(label='First Name' description='First name of the current user.')
        public String firstName;

        @InvocableVariable(label='Last Name' description='Last name of the current user.')
        public String lastName;

        @InvocableVariable(label='Email' description='Email address of the current user.')
        public String email;

        @InvocableVariable(label='Username' description='Salesforce username of the current user.')
        public String username;

        @InvocableVariable(label='Alias' description='Short alias of the current user.')
        public String alias;

        @InvocableVariable(label='Title' description='Job title of the current user.')
        public String title;

        @InvocableVariable(label='Department' description='Department of the current user.')
        public String department;

        @InvocableVariable(label='Division' description='Division of the current user.')
        public String division;

        @InvocableVariable(label='Company Name' description='Company name on the current user record.')
        public String companyName;

        @InvocableVariable(label='Employee Number' description='Employee number of the current user.')
        public String employeeNumber;

        @InvocableVariable(label='Phone' description='Phone number of the current user.')
        public String phone;

        @InvocableVariable(label='Mobile Phone' description='Mobile phone number of the current user.')
        public String mobilePhone;

        @InvocableVariable(label='Profile Id' description='Id of the current user\'s profile.')
        public Id profileId;

        @InvocableVariable(label='Profile Name' description='Name of the current user\'s profile (e.g. "System Administrator").')
        public String profileName;

        @InvocableVariable(label='Role Id' description='Id of the current user\'s role. Absent when the user has no role.')
        public Id roleId;

        @InvocableVariable(label='Role Name' description='Name of the current user\'s role. Absent when the user has no role.')
        public String roleName;

        @InvocableVariable(label='Manager Id' description='User Id of the current user\'s manager. Absent when no manager is set.')
        public Id managerId;

        @InvocableVariable(label='Manager Name' description='Full name of the current user\'s manager. Absent when no manager is set.')
        public String managerName;

        @InvocableVariable(label='User Type' description='License type of the current user (e.g. "Standard", "PowerPartner").')
        public String userType;

        @InvocableVariable(label='Time Zone' description='Time zone of the current user (e.g. "Asia/Kolkata"). Use it to interpret and present dates and times.')
        public String timeZone;

        @InvocableVariable(label='Locale' description='Locale of the current user (e.g. "en_US"). Use it to format numbers, dates and currency.')
        public String locale;

        @InvocableVariable(label='Language' description='Language of the current user (e.g. "en_US").')
        public String language;

        @InvocableVariable(label='Currency' description='Default currency ISO code of the current user, or the org currency in a single-currency org.')
        public String currencyIsoCode;

        @InvocableVariable(label='Last Login' description='When the current user last logged in.')
        public Datetime lastLoginDate;
    }

    @InvocableMethod(label='Get Current User' description='Returns details of the Salesforce user you are acting as: Id, name, email, username, title, department, profile, role, manager, user type, time zone, locale and currency.\n\nWhen to use:\n\nAt the start of a conversation, so you know who you are talking to.\nThe user says "me", "my" or "mine" (e.g. "my open opportunities", "cases assigned to me") and you need their User Id to filter on OwnerId, CreatedById or similar.\nYou need their manager, role or profile to answer the question.\nYou need their time zone or locale to present dates, times, numbers or currency.\n\nWhen not to use:\n\nYou already called it in this conversation; the result does not change.\nYou need another user\'s details; query the User object instead.')
    public static List<Output> run() {
        try {
            return new List<Output>{ buildOutput(queryCurrentUser()) };
        } catch (Exception e) {
            ApexAgentToolErrorContext.record(e);
            throw e;
        }
    }

    // Reads only the caller's own record. System mode so a user without access to
    // Profile, UserRole or other users' records still learns their own profile,
    // role and manager name; nothing about any other user is returned.
    @SuppressWarnings('PMD.ApexCRUDViolation')
    private static User queryCurrentUser() {
        Id currentUserId = UserInfo.getUserId();
        return [
            SELECT Id, Name, FirstName, LastName, Email, Username, Alias, Title, Department, Division,
                CompanyName, EmployeeNumber, Phone, MobilePhone, ProfileId, Profile.Name,
                UserRoleId, UserRole.Name, ManagerId, Manager.Name, UserType,
                TimeZoneSidKey, LocaleSidKey, LanguageLocaleKey, LastLoginDate
            FROM User
            WHERE Id = :currentUserId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
    }

    private static Output buildOutput(User u) {
        Output o = new Output();
        o.userId          = u.Id;
        o.name            = u.Name;
        o.firstName       = u.FirstName;
        o.lastName        = u.LastName;
        o.email           = u.Email;
        o.username        = u.Username;
        o.alias           = u.Alias;
        o.title           = u.Title;
        o.department      = u.Department;
        o.division        = u.Division;
        o.companyName     = u.CompanyName;
        o.employeeNumber  = u.EmployeeNumber;
        o.phone           = u.Phone;
        o.mobilePhone     = u.MobilePhone;
        o.profileId       = u.ProfileId;
        o.profileName     = u.Profile?.Name;
        o.roleId          = u.UserRoleId;
        o.roleName        = u.UserRole?.Name;
        o.managerId       = u.ManagerId;
        o.managerName     = u.Manager?.Name;
        o.userType        = u.UserType;
        o.timeZone        = u.TimeZoneSidKey;
        o.locale          = u.LocaleSidKey;
        o.language        = u.LanguageLocaleKey;
        o.currencyIsoCode = UserInfo.getDefaultCurrency();
        o.lastLoginDate   = u.LastLoginDate;
        return o;
    }
}
