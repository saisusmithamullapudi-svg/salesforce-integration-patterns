/**
 * Inbound webhook: the financing provider calls this endpoint when an
 * application's decision changes.
 *
 *   POST /services/apexrest/financing/v1/status
 *   { "applicationId": "APP-1001", "status": "APPROVED", "message": "..." }
 *
 * Exposed through a Connected App / integration user with the minimum
 * permissions needed; the provider authenticates with OAuth 2.0 client
 * credentials. The handler validates input, updates the matching Opportunity
 * by its external reference, and publishes a Platform Event for subscribers.
 */
@RestResource(urlMapping='/financing/v1/status')
global with sharing class FinancingStatusWebhook {
    global class StatusUpdate {
        global String applicationId;
        global String status;
        global String message;
    }

    global class Result {
        global Boolean success;
        global String error;
        Result(Boolean success, String error) {
            this.success = success;
            this.error = error;
        }
    }

    @HttpPost
    global static Result receive() {
        RestResponse res = RestContext.response;
        StatusUpdate payload;
        try {
            payload = (StatusUpdate) JSON.deserializeStrict(
                RestContext.request.requestBody.toString(),
                StatusUpdate.class
            );
        } catch (Exception e) {
            res.statusCode = 400;
            return new Result(false, 'Malformed JSON payload');
        }

        if (String.isBlank(payload.applicationId) || !FinancingStatusMapper.isKnown(payload.status)) {
            res.statusCode = 422;
            return new Result(false, 'applicationId and a known status are required');
        }

        List<Opportunity> matches = [
            SELECT Id, Financing_Status__c
            FROM Opportunity
            WHERE Financing_Reference__c = :payload.applicationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (matches.isEmpty()) {
            res.statusCode = 404;
            return new Result(false, 'Unknown applicationId');
        }

        Opportunity opp = matches[0];
        opp.Financing_Status__c = FinancingStatusMapper.toPicklist(payload.status);
        opp.Financing_Message__c = payload.message == null ? null : payload.message.abbreviate(255);
        update as user opp;

        EventBus.publish(
            new Financing_Status_Event__e(
                Opportunity_Id__c = opp.Id,
                Status__c = opp.Financing_Status__c,
                Reference__c = payload.applicationId
            )
        );

        res.statusCode = 200;
        return new Result(true, null);
    }
}
