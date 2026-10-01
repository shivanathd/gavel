@IsTest
private class Gavel_AdminController_Test {
    @IsTest
    static void consoleApi() {
        Gavel_TestFactory.register(Gavel_TestFactory.triage('Admin_Triage'));
        // The console runs in user mode: the admin needs the Gavel_Admin permission set (FLS on Gavel objects).
        User admin = Gavel_TestFactory.user('System Administrator');
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert new PermissionSetAssignment(AssigneeId = admin.Id, PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Gavel_Admin'].Id);
        }
        System.runAs(admin) {
            runConsole();
        }
    }

    private static void runConsole() {
        List<Map<String, Object>> defs = Gavel_AdminController.listDefinitions();
        Boolean found = false;
        for (Map<String, Object> d : defs) {
            if ((String) d.get('apiName') == 'Admin_Triage') {
                found = true;
                Assert.areEqual(true, d.get('valid'));
                Assert.areEqual('Shadow', d.get('mode'));
            }
        }
        Assert.isTrue(found);
        Map<String, Object> status = Gavel_AdminController.opsStatus();
        Assert.areEqual(false, status.get('egressEnabled'), 'egress off by default');
        Assert.areEqual('insufficient_calibration_sample', Gavel_AdminController.promotionStatus('Admin_Triage').reason);
        Assert.isFalse(Gavel_AdminController.changeMode('Admin_Triage', 'Live').accepted);
        Assert.isNull(Gavel_AdminController.latestCalibration('Admin_Triage'));
        Assert.isTrue(Gavel_AdminController.disagreement('Admin_Triage').contains('questions'));
        Test.startTest();
        Assert.isNotNull(Gavel_AdminController.runCalibration('Admin_Triage'));
        Test.stopTest();
        Assert.isNotNull(Gavel_AdminController.latestCalibration('Admin_Triage'));
    }
}
