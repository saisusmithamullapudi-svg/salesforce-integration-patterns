/**
 * Outbound REST client for a (synthetic) third-party financing provider.
 *
 * - Endpoint and authentication live in the Financing_API Named Credential /
 *   External Credential, so no URLs or secrets are stored in code.
 * - Sends an Idempotency-Key so a retried request cannot create a duplicate
 *   application on the provider side.
 * - Retries transient failures (HTTP 429/5xx and callout timeouts) with a
 *   bounded number of attempts; fails fast on 4xx validation errors.
 */
public with sharing class FinancingApiClient {
    @TestVisible
    private static final String NAMED_CREDENTIAL = 'callout:Financing_API';
    @TestVisible
    private static final Integer MAX_ATTEMPTS = 3;
    private static final Integer TIMEOUT_MS = 20000;
    private static final Set<Integer> RETRYABLE = new Set<Integer>{ 429, 500, 502, 503, 504 };

    public class ApplicationRequest {
        public String externalId; // Salesforce Opportunity Id
        public String applicantName;
        public Decimal systemPrice;
        public Integer termMonths;
        public String postalCode;
    }

    public class ApplicationResponse {
        public String applicationId;
        public String status; // SUBMITTED | APPROVED | DECLINED
        public String message;
    }

    public class FinancingApiException extends Exception {
        public Integer statusCode;
        public Boolean retryable = false;
    }

    public ApplicationResponse submitApplication(ApplicationRequest request) {
        HttpRequest http = new HttpRequest();
        http.setEndpoint(NAMED_CREDENTIAL + '/v1/applications');
        http.setMethod('POST');
        http.setTimeout(TIMEOUT_MS);
        http.setHeader('Content-Type', 'application/json');
        http.setHeader('Idempotency-Key', request.externalId);
        http.setBody(JSON.serialize(request, true));

        HttpResponse response = sendWithRetry(http);
        return (ApplicationResponse) JSON.deserialize(response.getBody(), ApplicationResponse.class);
    }

    @TestVisible
    private HttpResponse sendWithRetry(HttpRequest request) {
        FinancingApiException lastError;
        for (Integer attempt = 1; attempt <= MAX_ATTEMPTS; attempt++) {
            try {
                HttpResponse response = new Http().send(request);
                Integer code = response.getStatusCode();
                if (code >= 200 && code < 300) {
                    return response;
                }
                lastError = buildError(code, response.getBody());
                if (!lastError.retryable) {
                    throw lastError;
                }
            } catch (CalloutException e) {
                // Read timeouts and connection resets are transient.
                lastError = new FinancingApiException('Callout failed: ' + e.getMessage());
                lastError.retryable = true;
            }
            Logger.info('FinancingApiClient', 'Attempt ' + attempt + ' failed: ' + lastError.getMessage());
        }
        throw lastError;
    }

    private static FinancingApiException buildError(Integer code, String body) {
        FinancingApiException err = new FinancingApiException(
            'Financing API returned HTTP ' + code + ': ' + (body == null ? '' : body.abbreviate(255))
        );
        err.statusCode = code;
        err.retryable = RETRYABLE.contains(code);
        return err;
    }
}
