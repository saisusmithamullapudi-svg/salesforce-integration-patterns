/**
 * Configurable HttpCalloutMock that returns a scripted sequence of responses,
 * so tests can exercise success, validation errors, retries and timeouts.
 */
@IsTest
public class FinancingApiMock implements HttpCalloutMock {
    public class Step {
        public Integer statusCode;
        public String body;
        public Boolean throwTimeout = false;
        public Step(Integer statusCode, String body) {
            this.statusCode = statusCode;
            this.body = body;
        }
    }

    private final List<Step> steps;
    public Integer callCount = 0;
    public List<HttpRequest> requests = new List<HttpRequest>();

    public FinancingApiMock(List<Step> steps) {
        this.steps = steps;
    }

    public static FinancingApiMock always(Integer statusCode, String body) {
        return new FinancingApiMock(new List<Step>{ new Step(statusCode, body) });
    }

    public HttpResponse respond(HttpRequest request) {
        requests.add(request);
        Step step = steps[Math.min(callCount, steps.size() - 1)];
        callCount++;
        if (step.throwTimeout) {
            throw new CalloutException('Read timed out');
        }
        HttpResponse response = new HttpResponse();
        response.setStatusCode(step.statusCode);
        response.setHeader('Content-Type', 'application/json');
        response.setBody(step.body);
        return response;
    }
}
