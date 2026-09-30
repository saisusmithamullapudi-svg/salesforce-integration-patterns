@IsTest
private class FinancingSubmissionQueueableTest {
    @TestSetup
    static void setup() {
        Account acct = new Account(Name = 'Synthetic Homeowner', BillingPostalCode = '75009');
        insert acct;
        List<Opportunity> opps = new List<Opportunity>();
        for (Integer i = 0; i < 3; i++) {
            opps.add(
                new Opportunity(
                    Name = 'Rooftop system ' + i,
                    AccountId = acct.Id,
                    Amount = 30000 + i,
                    StageName = 'Prospecting',
                    CloseDate = Date.today().addDays(30),
                    Financing_Status__c = 'Not Submitted'
                )
            );
        }
        insert opps;
    }

    @IsTest
    static void submitsAndStoresReference() {
        Test.setMock(
            HttpCalloutMock.class,
            FinancingApiMock.always(201, '{"applicationId":"APP-9","status":"SUBMITTED","message":"Received"}')
        );
        List<Id> ids = new List<Id>(new Map<Id, Opportunity>([SELECT Id FROM Opportunity]).keySet());

        Test.startTest();
        System.enqueueJob(new FinancingSubmissionQueueable(ids));
        Test.stopTest();

        for (Opportunity opp : [SELECT Financing_Status__c, Financing_Reference__c FROM Opportunity]) {
            Assert.areEqual('Submitted', opp.Financing_Status__c);
            Assert.areEqual('APP-9', opp.Financing_Reference__c);
        }
    }

    @IsTest
    static void marksErrorWithoutFailingTheJob() {
        Test.setMock(HttpCalloutMock.class, FinancingApiMock.always(400, '{"error":"invalid term"}'));
        List<Id> ids = new List<Id>(new Map<Id, Opportunity>([SELECT Id FROM Opportunity]).keySet());

        Test.startTest();
        System.enqueueJob(new FinancingSubmissionQueueable(ids));
        Test.stopTest();

        for (Opportunity opp : [SELECT Financing_Status__c, Financing_Message__c FROM Opportunity]) {
            Assert.areEqual('Error', opp.Financing_Status__c);
            Assert.isTrue(opp.Financing_Message__c.contains('HTTP 400'));
        }
    }

    @IsTest
    static void skipsAlreadySubmittedRecords() {
        Opportunity opp = [SELECT Id FROM Opportunity LIMIT 1];
        opp.Financing_Status__c = 'Approved';
        update opp;
        FinancingApiMock mock = FinancingApiMock.always(201, '{"applicationId":"APP-1","status":"SUBMITTED"}');
        Test.setMock(HttpCalloutMock.class, mock);

        Test.startTest();
        System.enqueueJob(new FinancingSubmissionQueueable(new List<Id>{ opp.Id }));
        Test.stopTest();

        Assert.areEqual(0, mock.callCount, 'Approved applications must not be resubmitted');
    }
}
