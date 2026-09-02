/** 
* @Class Name	: SAIdSearchController 
* @Author		: Dreamwares 
* @CreateDate	: 27-08-2026 
* @Purpose		: Controller class used by the LWC to: 
* 					1. Validate and decode a South African ID number. 
* 					2. Retrieve relevant public holidays from Calendarific. 
* 					3. Persist the search information. 
* 					4. Return the processed result to the LWC. 
*/
public without sharing class SAIdSearchController {
    
    /**   
    * @Purpose		: To Validate SAID number, calling the Calendarific api, create the SAId number record if found
    * 				  Return wrapper class to saIdHolidaySearch lwc to show the processed result on the UI.
    * @Param		: South African Id Number (saIdNumber)
    * @Return		: SAIdSearchResultWrapper
    **/
    @AuraEnabled
    public static SAIdSearchResultWrapper searchBySouthAfricanIdNumber(String saIdNumber) {
        SAIdSearchResultWrapper payload = new SAIdSearchResultWrapper();        
        payload.transactionReferenceId = UUID.randomUUID().toString();
        payload.publicHolidayInfoList = new List<PublicHolidayInfoDTO>();
        
        try {
            SAIdParseOutcomeWrapper parseOutcome = SAIdDecoder.validateAndDecode(saIdNumber);            
               if (!parseOutcome.isValidResult) {
                payload.isSuccess = false;
                payload.statusMessage = parseOutcome.errorMessage;              
                return payload;
            }
           
            // Callout first - after the publish below, Apex would block it.
            CalendarificAPIService.HolidayResponse holidays =
                CalendarificAPIService.getHolidays(parseOutcome.dobYear);
           
            String holidayStatus;
            String apiStatus;
            String apiError;
            if (holidays.success == true) {
                holidayStatus = holidays.holidays.isEmpty() ? 'Empty' : 'Retrieved';
                apiStatus = 'Success';
            } else {
                holidayStatus = 'Failed';
                apiStatus = 'Error';             
                apiError = holidays.statusCode;
            }
            
            SAIdIdAPIService.PersistResult saved = SAIdIdAPIService.recordSearch(
                parseOutcome,
                saIdNumber,
                holidayStatus,
                apiStatus,
                apiError,
                payload.transactionReferenceId
            );
             
            payload.isSuccess = true;
            payload.dateOfBirth = parseOutcome.dateOfBirth;
            payload.dobYear = parseOutcome.dobYear;
            payload.gender = parseOutcome.genderCode;
            payload.citizenship = parseOutcome.citizenship;            
            payload.searchCount = saved.searchCount;
            payload.isHolidaysAvailable = holidays.success == true;
            payload.publicHolidayInfoList = holidays.holidays;
            payload.holidayMessage = holidays.userMessage;          
            payload.currentYear = System.now().year();
            System.debug('#payload:'+ JSON.Serialize(payload));
            return payload;
        } catch (Exception ex) {  
            try { 
                ErrorLogger.logException( ex, 'SAIdSearchController', 'searchBySouthAfricanIdNumber', payload.transactionReferenceId ); 
            } catch (Exception loggingException) { 
                /* * Error logging itself must never prevent the * original exception from being handled. */ 
                System.debug( LoggingLevel.ERROR, '# ErrorLogger failed: ' + loggingException.getMessage() ); 
            }
            payload.isSuccess = false;
            payload.statusMessage = 'Something went wrong while processing your request. Please try again.';            
            return payload;
        }
    }

    
}