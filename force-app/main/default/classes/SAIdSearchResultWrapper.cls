/** 
 * @Class Name	: SAIdHolidaySearchResultDTO
 * @Author		: Dreamwares
 * @CreateDate	: 27-08-2026
 * @Purpose		: Wrapper class to send the extracted details based on the
 * 				  South Africa Id Number with respective list of current year holidays to the 'saIdHolidaySearch' lwc component.
 **/
public without sharing class SAIdSearchResultWrapper {
    @AuraEnabled public Boolean isSuccess;
    @AuraEnabled public Boolean isHolidaysAvailable;
    @AuraEnabled public String transactionReferenceId;
    @AuraEnabled public Date dateOfBirth;
    @AuraEnabled public Integer dobMonth;
    @AuraEnabled public Integer dobDay;
    @AuraEnabled public Integer dobYear;
    @AuraEnabled public String gender;
    @AuraEnabled public String citizenship;
    @AuraEnabled public String statusMessage;
    @AuraEnabled public String holidayMessage;
    @AuraEnabled public Integer currentYear;
    @AuraEnabled public List<PublicHolidayInfoDTO> publicHolidayInfoList;
    public Integer searchCount;
}