@IsTest
private class ApexAgentGetCurrentUserTest {

    // ─── Happy path — direct static call ─────────────────────────────────────────

    @IsTest
    static void testReturnsRunningUserWithProfileRoleAndManager() {
        UserRole role = new UserRole(Name = 'ApexAgent Test Role', DeveloperName = 'ApexAgentTestRole' + uniqueSuffix());
        insert role;
        User manager = newUser('Manager', null, null);
        insert manager;
        // A minimum-access user proves the tool still returns profile, role and manager
        // details to someone with almost no permissions
        User member = newUser('Member', role.Id, manager.Id);
        member.ProfileId = [SELECT Id FROM Profile WHERE Name = 'Minimum Access - Salesforce' LIMIT 1].Id;
        member.Title = 'Solutions Engineer';
        member.Department = 'Engineering';
        insert member;

        List<ApexAgentGetCurrentUser.Output> results;
        System.runAs(member) {
            results = ApexAgentGetCurrentUser.run();
        }

        Assert.areEqual(1, results.size(), 'Exactly one result expected');
        ApexAgentGetCurrentUser.Output o = results[0];
        User expected = [SELECT Name, Profile.Name FROM User WHERE Id = :member.Id];
        Assert.areEqual(member.Id, o.userId, 'userId should be the running user');
        Assert.areEqual(expected.Name, o.name, 'name should match');
        Assert.areEqual(member.Email, o.email, 'email should match');
        Assert.areEqual(member.Username, o.username, 'username should match');
        Assert.areEqual('Solutions Engineer', o.title, 'title should match');
        Assert.areEqual('Engineering', o.department, 'department should match');
        Assert.areEqual(member.ProfileId, o.profileId, 'profileId should match');
        Assert.areEqual(expected.Profile.Name, o.profileName, 'profileName should come from the profile');
        Assert.areEqual(role.Id, o.roleId, 'roleId should match');
        Assert.areEqual('ApexAgent Test Role', o.roleName, 'roleName should come from the role');
        Assert.areEqual(manager.Id, o.managerId, 'managerId should match');
        Assert.areEqual([SELECT Name FROM User WHERE Id = :manager.Id].Name, o.managerName, 'managerName should come from the manager');
        Assert.areEqual('Standard', o.userType, 'userType should be Standard');
        Assert.areEqual('Asia/Kolkata', o.timeZone, 'timeZone should match');
        Assert.areEqual('en_US', o.locale, 'locale should match');
        Assert.areEqual('en_US', o.language, 'language should match');
        Assert.isNotNull(o.currencyIsoCode, 'currencyIsoCode should always be set');

        // A user with no role or manager gets those fields left empty, not an error
        System.runAs(manager) {
            results = ApexAgentGetCurrentUser.run();
        }
        Assert.areEqual(manager.Id, results[0].userId, 'userId should be the manager');
        Assert.isNull(results[0].roleName, 'roleName should be null without a role');
        Assert.isNull(results[0].managerId, 'managerId should be null without a manager');
        Assert.isNull(results[0].managerName, 'managerName should be null without a manager');
    }

    // ─── Happy path — through the real Invocable.Action dispatch path ────────────

    @IsTest
    static void testHappyPathViaToolExecutor() {
        Test.startTest();
        String output = ApexAgentToolExecutor.executeInline('ApexAgentGetCurrentUser', new Map<String, Object>());
        Test.stopTest();

        Map<String, Object> parsed = (Map<String, Object>) JSON.deserializeUntyped(output);
        Assert.areEqual(String.valueOf(UserInfo.getUserId()), parsed.get('userId'), 'userId should be the running user');
        Assert.areEqual(UserInfo.getUserEmail(), parsed.get('email'), 'email should match');
        Assert.areEqual(UserInfo.getUserName(), parsed.get('username'), 'username should match');
        Assert.isTrue(parsed.containsKey('profileName'), 'profileName should be returned');
    }

    // ─── Helpers ──────────────────────────────────────────────────────────────────

    private static User newUser(String lastName, Id roleId, Id managerId) {
        String suffix = uniqueSuffix();
        return new User(
            FirstName         = 'ApexAgent',
            LastName          = lastName,
            Alias             = lastName.left(4) + suffix.right(4),
            Email             = lastName.toLowerCase() + '@apexagent.test',
            Username          = lastName.toLowerCase() + suffix + '@apexagent.test',
            ProfileId         = UserInfo.getProfileId(),
            UserRoleId        = roleId,
            ManagerId         = managerId,
            TimeZoneSidKey    = 'Asia/Kolkata',
            LocaleSidKey      = 'en_US',
            LanguageLocaleKey = 'en_US',
            EmailEncodingKey  = 'UTF-8'
        );
    }

    private static String uniqueSuffix() {
        return String.valueOf(Crypto.getRandomInteger()).remove('-');
    }
}
