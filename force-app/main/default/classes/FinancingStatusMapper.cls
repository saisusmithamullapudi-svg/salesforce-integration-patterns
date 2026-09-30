/**
 * Maps provider status codes to the Opportunity.Financing_Status__c picklist.
 * Keeping the mapping in one place means a provider change touches one class.
 */
public with sharing class FinancingStatusMapper {
    private static final Map<String, String> STATUS_MAP = new Map<String, String>{
        'SUBMITTED' => 'Submitted',
        'IN_REVIEW' => 'Submitted',
        'APPROVED' => 'Approved',
        'DECLINED' => 'Declined'
    };

    public static String toPicklist(String providerStatus) {
        String key = providerStatus == null ? '' : providerStatus.trim().toUpperCase();
        return STATUS_MAP.containsKey(key) ? STATUS_MAP.get(key) : 'Error';
    }

    public static Boolean isKnown(String providerStatus) {
        return providerStatus != null && STATUS_MAP.containsKey(providerStatus.trim().toUpperCase());
    }
}
