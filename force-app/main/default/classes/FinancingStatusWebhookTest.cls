@IsTest
private class FinancingStatusWebhookTest {
    @TestSetup
    static void setup() {
        insert new Opportunity(
            Name = 'Rooftop system',
            StageName = 'Prospecting',
            CloseDate = Date.today().addDays(30),
            Financing_Status__c = 'Submitted',
            Financing_Reference__c = 'APP-500'
        );
    }

    private static FinancingStatusWebhook.Result post(String body) {
        RestRequest req = new RestRequest();
        req.requestURI = '/services/apexrest/financing/v1/status';
        req.httpMethod = 'POST';
        req.requestBody = Blob.valueOf(body);
        RestContext.request = req;
        RestContext.response = new RestResponse();
        return FinancingStatusWebhook.receive();
    }

    @IsTest
    static void updatesOpportunityOnValidPayload() {
        Test.startTest();
        FinancingStatusWebhook.Result result = post('{"applicationId":"APP-500","status":"APPROVED","message":"OK"}');
        Test.stopTest();

        Assert.isTrue(result.success);
        Assert.areEqual(200, RestContext.response.statusCode);
        Assert.areEqual('Approved', [SELECT Financing_Status__c FROM Opportunity LIMIT 1].Financing_Status__c);
    }

    @IsTest
    static void rejectsMalformedJson() {
        FinancingStatusWebhook.Result result = post('{not json');
        Assert.isFalse(result.success);
        Assert.areEqual(400, RestContext.response.statusCode);
    }

    @IsTest
    static void rejectsUnknownStatus() {
        FinancingStatusWebhook.Result result = post('{"applicationId":"APP-500","status":"MAYBE"}');
        Assert.areEqual(422, RestContext.response.statusCode);
        Assert.isFalse(result.success);
    }

    @IsTest
    static void returnsNotFoundForUnknownApplication() {
        FinancingStatusWebhook.Result result = post('{"applicationId":"APP-404","status":"DECLINED"}');
        Assert.areEqual(404, RestContext.response.statusCode);
        Assert.isFalse(result.success);
    }
}
