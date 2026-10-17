/**
 * Test data builders shared by every Gavel package's tests.
 * Definitions are built in memory and registered with Gavel_DefinitionRepo (CMDT cannot be inserted in tests).
 */
@IsTest
public class Gavel_TestFactory {
    public static final String MOCK_PROVIDER = 'Gavel_MockProvider';
    public static final String PINNED_MODEL = 'jev-1.13.0';

    public static Gavel_Question choice(String key, List<String> optionKeys) {
        Gavel_Question q = new Gavel_Question(key, Gavel_Question.CHOICE, 'Which ' + key + ' applies?');
        Integer i = 0;
        for (String k : optionKeys) {
            Gavel_Option o = new Gavel_Option(k, k.toLowerCase().capitalize());
            o.sortOrder = i++;
            q.options.add(o);
        }
        return q;
    }

    public static Gavel_Question score(String key, Integer fromLevel, Integer toLevel) {
        Gavel_Question q = new Gavel_Question(key, Gavel_Question.SCORE, 'How much ' + key + '?');
        for (Integer l = fromLevel; l <= toLevel; l++) {
            Gavel_Option o = new Gavel_Option('L' + l, 'Level ' + l);
            o.level = l;
            q.options.add(o);
        }
        return q;
    }

    public static Gavel_Question noul(String key) {
        return new Gavel_Question(key, Gavel_Question.NOUL, 'It is true that ' + key + '.');
    }

    /** Box question (Jev 1.14): never required for action. */
    public static Gavel_Question box(String key) {
        Gavel_Question q = new Gavel_Question(key, Gavel_Question.BOX, 'Where is the ' + key + '?');
        q.requiredForAction = false;
        return q;
    }

    /** A valid 300x300 PNG, within the side lengths TypeSafe accepts. */
    public static Blob png() {
        return EncodingUtil.base64Decode('iVBORw0KGgoAAAANSUhEUgAAASwAAAEsAQAAAABRBrPYAAAAQElEQVR42u3KMQEAAAQAMPQvKwGvU4DtXk48dMWLpmmapmmapmmapmmapmmapmmapmmapmmapmmapmmapmmadi0s8QRIt0bcDwAAAABJRU5ErkJggg==');
    }

    /** Attaches an image file to a record, the way a user upload or Email-to-Case does. */
    public static ContentVersion attachImage(Id recordId, String fileName, Blob data) {
        ContentVersion cv = new ContentVersion(Title = fileName, PathOnClient = fileName, VersionData = data, FirstPublishLocationId = recordId);
        insert cv;
        return cv;
    }

    public static Gavel_Definition.Policy policy(String key, Decimal autoAccept, Decimal reviewAt, Decimal minMargin) {
        return new Gavel_Definition.Policy(key, autoAccept, reviewAt, minMargin);
    }

    public static Gavel_Definition.Policy noulPolicy(String key, Decimal autoAccept, Decimal reviewAt, String direction) {
        Gavel_Definition.Policy p = new Gavel_Definition.Policy(key, autoAccept, reviewAt, null);
        p.noulDirection = direction;
        return p;
    }

    /** Empty definition shell on a target object, Shadow mode, mock provider, pinned model. */
    public static Gavel_Definition definition(String apiName, String targetObject) {
        Gavel_Definition d = new Gavel_Definition();
        d.apiName = apiName;
        d.targetObject = targetObject;
        d.version = 1;
        d.mode = Gavel_Definition.MODE_SHADOW;
        d.providerConfig = 'Mock';
        d.providerClass = MOCK_PROVIDER;
        d.model = PINNED_MODEL;
        d.timeoutMs = 10000;
        d.autoApply = true;
        return d;
    }

    /**
     * Case triage shape used across tests: Choice "category" (BILLING, FRAUD, TECHNICAL, ACCOUNT)
     * plus Noul "fraud_concern"; state = Subject, Description (required).
     */
    public static Gavel_Definition triage(String apiName) {
        Gavel_Definition d = definition(apiName, 'Case');
        d.questions.add(choice('category', new List<String>{ 'BILLING', 'FRAUD', 'TECHNICAL', 'ACCOUNT' }));
        Gavel_Question fraud = noul('fraud_concern');
        fraud.requiredForAction = false;
        d.questions.add(fraud);
        d.policies.add(policy('category', 0.85, 0.5, 0.3));
        d.policies.add(noulPolicy('fraud_concern', 0.85, 0.5, 'true_is_action'));
        d.stateFields.add(new Gavel_Definition.StateField('Subject', 'subject', false));
        d.stateFields.add(new Gavel_Definition.StateField('Description', 'description', true));
        return d;
    }

    /** Computes and stores the canonical hash, as CI does for shipped definitions. */
    public static Gavel_Definition seal(Gavel_Definition d) {
        d.definitionHash = Gavel_DefinitionHasher.compute(d);
        return d;
    }

    public static Gavel_Definition register(Gavel_Definition d) {
        seal(d);
        Gavel_DefinitionRepo.registerForTest(d);
        return d;
    }

    /** Ops config override for the current test (egress on/off). */
    public static Gavel_Config.Ops ops(Boolean egressEnabled) {
        Gavel_Config.Ops o = new Gavel_Config.Ops();
        o.egressEnabled = egressEnabled;
        Gavel_Config.opsOverride = o;
        return o;
    }

    /**
     * Inserts an active user with the given profile (falls back to Standard User). Call from a test before
     * creating records; setup DML runs as the current user to avoid mixed DML.
     */
    public static User user(String profileName) {
        List<Profile> profiles = [SELECT Id FROM Profile WHERE Name = :profileName LIMIT 1];
        if (profiles.isEmpty()) {
            profiles = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1];
        }
        String unique = String.valueOf(Crypto.getRandomInteger()).replace('-', '') + String.valueOf(System.now().getTime());
        User u = new User(
            ProfileId = profiles[0].Id,
            Username = 'gavel.' + unique + '@example.gavel.test',
            Email = 'gavel.test@example.com',
            LastName = 'Gavel Test',
            Alias = 'gtst' + unique.right(4),
            TimeZoneSidKey = 'America/Los_Angeles',
            LocaleSidKey = 'en_US',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            insert u;
        }
        return u;
    }

    /** Grants object CRUD (no field permissions) to a user through a throwaway permission set. */
    public static void grantObject(User u, String sobjectType, Boolean canEdit) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet ps = new PermissionSet(Name = 'Gavel_Test_' + sobjectType.replace('__', '_') + '_' + String.valueOf(Crypto.getRandomInteger()).replace('-', ''), Label = 'Gavel Test ' + sobjectType);
            insert ps;
            insert new ObjectPermissions(
                ParentId = ps.Id,
                SobjectType = sobjectType,
                PermissionsRead = true,
                PermissionsCreate = canEdit,
                PermissionsEdit = canEdit
            );
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }

    public static Case newCase(String subject, String description) {
        return new Case(Subject = subject, Description = description, Origin = 'Web', Status = 'New');
    }

    /** Read + View All on an object and read FLS on the given fields, through a throwaway permission set. */
    public static void grantRead(User u, String sobjectType, List<String> fields) {
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet ps = new PermissionSet(
                Name = 'Gavel_Read_' + String.valueOf(Crypto.getRandomInteger()).replace('-', ''),
                Label = 'Gavel Test Read ' + sobjectType
            );
            insert ps;
            insert new ObjectPermissions(ParentId = ps.Id, SobjectType = sobjectType, PermissionsRead = true, PermissionsViewAllRecords = true);
            List<FieldPermissions> fps = new List<FieldPermissions>();
            for (String f : fields) {
                fps.add(new FieldPermissions(ParentId = ps.Id, SobjectType = sobjectType, Field = sobjectType + '.' + f, PermissionsRead = true));
            }
            insert fps;
            insert new PermissionSetAssignment(AssigneeId = u.Id, PermissionSetId = ps.Id);
        }
    }
}
