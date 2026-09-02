/** 
 * @Class Name	: SAIdParseOutcomeWrapper
 * @Author		: Dreamwares
 * @CreateDate	: 27-08-2026
 * @Purpose		: Used as Wrapper to map the values after extracting the South Africa Id Number
 */
public with sharing class SAIdParseOutcomeWrapper {
    @AuraEnabled public Boolean isValidResult;
    @AuraEnabled public Date dateOfBirth;
    @AuraEnabled public Integer dobYear;
    @AuraEnabled public Integer dobMonth;
    @AuraEnabled public Integer dobDay;
    @AuraEnabled public String genderCode;
    @AuraEnabled public String citizenship;
    @AuraEnabled public String errorCode;
    @AuraEnabled public String errorMessage;
    public String normalizedId;
}