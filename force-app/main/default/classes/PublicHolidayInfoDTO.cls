/** 
 * @Class Name	: PublicHolidayInfoDTO
 * @Author		: Dreamwares
 * @CreateDate	: 27-08-2026
 * @Purpose		: Wrapper class for a single public holiday returned to the LWC.
 * 				  Holiday list returned by the Calendarific API.
 **/
public without sharing class PublicHolidayInfoDTO {
    @AuraEnabled public String holidayName;
    @AuraEnabled public String holidayDate;
    @AuraEnabled public String holidayDescription;
    @AuraEnabled public String holidayCategory;
    @AuraEnabled public String holidayPrimaryType;
    @AuraEnabled public String holidayLocation;
    @AuraEnabled public String holidayCountry;
    @AuraEnabled public String currentYear;
}