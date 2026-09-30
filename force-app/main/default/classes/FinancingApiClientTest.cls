@IsTest
private class FinancingApiClientTest {
    private static FinancingApiClient.ApplicationRequest sampleRequest() {
        FinancingApiClient.ApplicationRequest request = new FinancingApiClient.ApplicationRequest();
        request.externalId = '006000000000001AAA';
        request.applicantName = 'Synthetic Homeowner';
        request.systemPrice = 32000;
        request.termMonths = 240;
        request.postalCode = '75009';
        return request;
    }

    @IsTest
    static void returnsParsedResponseOnSuccess() {
        FinancingApiMock mock = FinancingApiMock.always(201, '{"applicationId":"APP-1","status":"SUBMITTED"}');
        Test.setMock(HttpCalloutMock.class, mock);

        FinancingApiClient.ApplicationResponse response = new FinancingApiClient().submitApplication(sampleRequest());

        Assert.areEqual('APP-1', response.applicationId);
        Assert.areEqual('SUBMITTED', response.status);
        HttpRequest sent = mock.requests[0];
        Assert.areEqual('callout:Financing_API/v1/applications', sent.getEndpoint());
        Assert.areEqual(
            '006000000000001AAA',
            sent.getHeader('Idempotency-Key'),
            'Idempotency key must be the record Id'
        );
    }

    @IsTest
    static void retriesTransientErrorsThenSucceeds() {
        FinancingApiMock.Step timeout = new FinancingApiMock.Step(0, null);
        timeout.throwTimeout = true;
        FinancingApiMock mock = new FinancingApiMock(
            new List<FinancingApiMock.Step>{
                new FinancingApiMock.Step(503, '{"error":"unavailable"}'),
                timeout,
                new FinancingApiMock.Step(200, '{"applicationId":"APP-2","status":"APPROVED"}')
            }
        );
        Test.setMock(HttpCalloutMock.class, mock);

        FinancingApiClient.ApplicationResponse response = new FinancingApiClient().submitApplication(sampleRequest());

        Assert.areEqual(3, mock.callCount, 'Should retry twice before succeeding');
        Assert.areEqual('APPROVED', response.status);
    }

    @IsTest
    static void doesNotRetryValidationErrors() {
        FinancingApiMock mock = FinancingApiMock.always(400, '{"error":"postalCode is required"}');
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            new FinancingApiClient().submitApplication(sampleRequest());
            Assert.fail('Expected FinancingApiException');
        } catch (FinancingApiClient.FinancingApiException e) {
            Assert.areEqual(400, e.statusCode);
            Assert.isFalse(e.retryable);
            Assert.areEqual(1, mock.callCount, '4xx errors must fail fast');
        }
    }

    @IsTest
    static void givesUpAfterMaxAttempts() {
        FinancingApiMock mock = FinancingApiMock.always(500, 'boom');
        Test.setMock(HttpCalloutMock.class, mock);

        try {
            new FinancingApiClient().submitApplication(sampleRequest());
            Assert.fail('Expected FinancingApiException');
        } catch (FinancingApiClient.FinancingApiException e) {
            Assert.areEqual(FinancingApiClient.MAX_ATTEMPTS, mock.callCount);
            Assert.isTrue(e.retryable);
        }
    }

    @IsTest
    static void mapsProviderStatuses() {
        Assert.areEqual('Approved', FinancingStatusMapper.toPicklist(' approved '));
        Assert.areEqual('Submitted', FinancingStatusMapper.toPicklist('IN_REVIEW'));
        Assert.areEqual('Error', FinancingStatusMapper.toPicklist('SOMETHING_NEW'));
        Assert.areEqual('Error', FinancingStatusMapper.toPicklist(null));
        Assert.isFalse(FinancingStatusMapper.isKnown(null));
    }
}
