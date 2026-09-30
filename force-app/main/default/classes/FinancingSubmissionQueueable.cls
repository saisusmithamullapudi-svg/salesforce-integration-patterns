/**
 * Submits Opportunities to the financing provider outside the user's
 * transaction (callouts are not allowed after uncommitted DML, and users
 * should not wait on a third-party API).
 *
 * Processes up to BATCH_SIZE records per job and chains itself for the rest,
 * keeping each execution well inside the 100-callout limit.
 */
public with sharing class FinancingSubmissionQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private static final Integer BATCH_SIZE = 50;
    @TestVisible
    private static Boolean chainingEnabled = !Test.isRunningTest();

    private final List<Id> opportunityIds;

    public FinancingSubmissionQueueable(List<Id> opportunityIds) {
        this.opportunityIds = opportunityIds;
    }

    public void execute(QueueableContext context) {
        List<Id> current = new List<Id>();
        List<Id> remaining = new List<Id>();
        for (Integer i = 0; i < opportunityIds.size(); i++) {
            if (i < BATCH_SIZE) {
                current.add(opportunityIds[i]);
            } else {
                remaining.add(opportunityIds[i]);
            }
        }

        List<Opportunity> opportunities = [
            SELECT Id, Name, Amount, Account.Name, Account.BillingPostalCode, Financing_Term_Months__c
            FROM Opportunity
            WHERE Id IN :current AND Financing_Status__c IN ('Not Submitted', 'Error')
            WITH USER_MODE
        ];

        FinancingApiClient client = new FinancingApiClient();
        List<Financing_Status_Event__e> events = new List<Financing_Status_Event__e>();

        for (Opportunity opp : opportunities) {
            FinancingApiClient.ApplicationRequest request = new FinancingApiClient.ApplicationRequest();
            request.externalId = opp.Id;
            request.applicantName = opp.Account?.Name;
            request.systemPrice = opp.Amount;
            request.termMonths = opp.Financing_Term_Months__c == null ? 240 : opp.Financing_Term_Months__c.intValue();
            request.postalCode = opp.Account?.BillingPostalCode;

            try {
                FinancingApiClient.ApplicationResponse response = client.submitApplication(request);
                opp.Financing_Reference__c = response.applicationId;
                opp.Financing_Status__c = FinancingStatusMapper.toPicklist(response.status);
                opp.Financing_Message__c = response.message;
            } catch (FinancingApiClient.FinancingApiException e) {
                opp.Financing_Status__c = 'Error';
                opp.Financing_Message__c = e.getMessage().abbreviate(255);
                Logger.error('FinancingSubmissionQueueable', opp.Id + ' ' + e.getMessage());
            }
            events.add(
                new Financing_Status_Event__e(
                    Opportunity_Id__c = opp.Id,
                    Status__c = opp.Financing_Status__c,
                    Reference__c = opp.Financing_Reference__c
                )
            );
        }

        Logger.logSaveErrors(
            'FinancingSubmissionQueueable',
            Database.update(opportunities, false, AccessLevel.USER_MODE)
        );
        if (!events.isEmpty()) {
            EventBus.publish(events);
        }

        if (!remaining.isEmpty() && chainingEnabled) {
            System.enqueueJob(new FinancingSubmissionQueueable(remaining));
        }
    }
}
