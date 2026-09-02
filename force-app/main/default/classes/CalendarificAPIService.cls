/**
 * @Class Name	: CalendarificAPIService
 * @Author		: Dreamwares
 * @CreateDate	: 27-08-2026
 * @Purpose		: Apex class to handle API callout to Calendarific API to fetch South African public holidays.  
 * @description	: This class is responsible for making HTTP callouts to the Calendarific API, parsing the response, and returning a list of public holidays. 
 *                  It also handles error logging and user-friendly messages for various failure scenarios.
 * 				  Holiday list returned by the Calendarific API.
 **/
public class CalendarificAPIService {

    /**
     * Holds Calendarific integration configuration.
     */
    private class CalendarificAPIConfig {
        String apiUrl;
        String apiKey;
    }
    /**    
     * @Purpose		: To read the Calendarific API key from the Calendarific_Custom_Setting__c custom setting.
     * 			  Logs a configuration exception and throws when the org default is missing or the key is blank.
     * @Param		: None
     **/
    private static String apiKey() {
        Calendarific_Custom_Setting__c secret = Calendarific_Custom_Setting__c.getOrgDefaults();
        if (secret == null || String.isBlank(secret.Calendarific_API_Key__c)) {            
            SAIdException configEx = new SAIdException(
                'CONFIG',
                'We could not retrieve the public holiday information at this time. Please try again later.'
            );
            throw configEx;
        }
        return secret.Calendarific_API_Key__c.trim();
    }
    /**    
     * @Purpose		: To read the Calendarific API URL and API key from the Integration_Secret__c custom setting.
     * 			  Returns them as an CalendarificAPIConfig instance, throwing when either value is not configured.
     * @Param		: None
     **/
    private static CalendarificAPIConfig getCalendarificAPIConfig() {
        Calendarific_Custom_Setting__c secret = Calendarific_Custom_Setting__c.getOrgDefaults();
        
        if (
            secret == null ||
            String.isBlank(secret.Calendarific_API_Key__c) ||
            String.isBlank(secret.Calendarific_API_Url__c)
        ) {
            SAIdException configEx = new SAIdException(
                'CONFIG',
                'We could not retrieve the public holiday information at this time. Please try again later.'
            );            
            throw configEx;
        }
        
        CalendarificAPIConfig config = new CalendarificAPIConfig();
        config.apiUrl = secret.Calendarific_API_Url__c.trim();
        config.apiKey = secret.Calendarific_API_Key__c.trim();
        
        return config;
    }
    
    /**
     * Holds the outcome of a holiday callout returned to the caller.
     */
    public class HolidayResponse {       
        public Boolean success;
        public String statusCode;
        public String userMessage;
        public List<PublicHolidayInfoDTO> holidays = new List<PublicHolidayInfoDTO>();
    }


    /**
     * @Purpose		: To call the Calendarific API and fetch the South African national public holidays for the current year.
     * 			  Returns a HolidayResponse carrying the success flag, status code, user message and holiday list,
     * 			  logging any validation, callout, HTTP or parsing failure along the way.
     * @Param		: Birth year decoded from the South Africa Id Number (year)
     **/
    public static HolidayResponse getHolidays(Integer year) {
        HolidayResponse result = new HolidayResponse();
        String currentYear = String.valueOf(System.now().year());
        
        if (year > 2049) {
            result.success = false;
            result.userMessage = 'Holiday information is not available for this birth year.';
            result.statusCode = 'YEAR_UNSUPPORTED';
            
           SAIdException ex = new SAIdException(
                'YEAR_UNSUPPORTED',
                'Unsupported birth year: ' + String.valueOf(year)
            );

            ErrorLogger.logException(
                ex,
                'CalendarificAPIService',
                'getHolidays',
                null
            );
           return result;
        }
        
		/*
         * Read API URL and API key from Custom Setting.
         */        CalendarificAPIConfig config =
            getCalendarificAPIConfig();
    
        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setTimeout(10000);
        req.setHeader('Accept', 'application/json');
        req.setEndpoint(
            config.apiUrl +
            '?api_key=' + EncodingUtil.urlEncode(config.apiKey, 'UTF-8') +
            '&country=ZA' +
            '&year=' + currentYear +
            '&type=national'
        );
       
        HttpResponse res;
        try {
            res = new Http().send(req);
        } catch (System.CalloutException ex) {
            result.success = false;
            result.statusCode = 'CALLOUT';
            result.userMessage =
                'We were able to validate your ID Number, but we could not retrieve the public holiday information at this time. Please try again later.';
            ErrorLogger.logException(
                    ex,
                    'CalendarificAPIService',
                    'getHolidays',
                    null
              );
            return result;
        }

        Integer httpCode = res.getStatusCode();
        if (httpCode != 200) {
            result.success = false;
            result.statusCode = String.valueOf(httpCode);
            result.userMessage = userMessageForHttp(httpCode);
            SAIdException ex = new SAIdException(
                'HTTP_' + String.valueOf(httpCode),
                'Calendarific API returned: ' + res.toString()
            );
        
            ErrorLogger.logException(
                ex,
                'CalendarificAPIService',
                'getHolidays',
                null
            );
            return result;
        }
        
        try {
            result.holidays = filterNationalHolidays(parseHolidays(res.getBody()));
        } catch (Exception parseEx) {
            result.success = false;
            result.statusCode = 'JSON';
            result.userMessage =
                'We were able to validate your ID Number, but holiday information was in an unexpected format. Please try again later.';
            ErrorLogger.logException(
                parseEx,
                'CalendarificAPIService',
                'getHolidays',
                null
            );
            return result;
        }

        result.success = true;
        result.statusCode = '200';
        // Success with nothing to show still needs an explanation in the UI.
        if (result.holidays.isEmpty()) {
            result.userMessage = 'No public holidays were found for your birth year.';
        }
        return result;
    }

    
    /**
     * @Purpose		: To parse the Calendarific JSON response body into a list of HolidayDto records.
     * 			  Throws a SouthAfricaIdException when the payload is not a Calendarific response.
     * @Param		: Raw JSON response body returned by the Calendarific API (body)
     **/
    @TestVisible
    static List<PublicHolidayInfoDTO> parseHolidays(String body) {
        List<PublicHolidayInfoDTO> output = new List<PublicHolidayInfoDTO>();
        Map<String, Object> root = (Map<String, Object>) JSON.deserializeUntyped(body);
        // No `response` node means this is not a Calendarific payload at all -
        // an error envelope or an HTML error page. Worth distinguishing from
        // a well-formed payload that simply lists nothing.
        if (root == null || !root.containsKey('response')) {
            throw new SAIdException('JSON', 'Unexpected response');
        }
        Object responseObj = root.get('response');
        if (!(responseObj instanceof Map<String, Object>)) {
            return output;
        }
        Map<String, Object> response = (Map<String, Object>) responseObj;
        Object holidaysObj = response.get('holidays');
        if (!(holidaysObj instanceof List<Object>)) {
            return output;
        }
        for (Object item : (List<Object>) holidaysObj) {
            Map<String, Object> h = (Map<String, Object>) item;
            PublicHolidayInfoDTO dto = new PublicHolidayInfoDTO();
            dto.holidayName = (String) h.get('name');
            dto.holidayDescription = (String) h.get('description');
            // `locations` is a free-text field, occasionally not a plain string.
            dto.holidayLocation = h.get('locations') == null ? null : String.valueOf(h.get('locations'));
            // date.iso is normally 'yyyy-MM-dd' but can carry a time or offset
            // for observance entries; trim to the date so the LWC can compare
            // birthdays with a plain MM-DD string match.
            Map<String, Object> dateNode = (Map<String, Object>) h.get('date');
            if (dateNode != null) {
                dto.holidayDate = String.valueOf(dateNode.get('iso'));
                if (dto.holidayDate != null && dto.holidayDate.length() >= 10) {
                    dto.holidayDate = dto.holidayDate.substring(0, 10);
                }
            }
            // `type` is an array; flatten it so isNationalHoliday() and the UI
            // both work off one string.
            Object typeObj = h.get('type');
            if (typeObj instanceof List<Object>) {
                List<String> types = new List<String>();
                for (Object t : (List<Object>) typeObj) {
                    types.add(String.valueOf(t));
                }
                dto.holidayCategory = String.join(types, ', ');
            }
            dto.holidayPrimaryType = h.get('primary_type') == null
                ? dto.holidayCategory
                : String.valueOf(h.get('primary_type'));
            Object countryObj = h.get('country');
            if (countryObj instanceof Map<String, Object>) {
                dto.holidayCountry = String.valueOf(((Map<String, Object>) countryObj).get('name'));
            } else {
                // Safe default: this service only ever queries country=ZA.
                dto.holidayCountry = 'South Africa';
            }
            output.add(dto);
        }
        return output;
    }

    
    /**
     * @Purpose		: To keep only the national public holidays from the parsed holiday list.
     * @Param		: Parsed holiday list returned by parseHolidays (holidays)
     **/
    @TestVisible
    static List<PublicHolidayInfoDTO> filterNationalHolidays(List<PublicHolidayInfoDTO> holidays) {
        List<PublicHolidayInfoDTO> national = new List<PublicHolidayInfoDTO>();
        if (holidays == null) {
            return national;
        }
        for (PublicHolidayInfoDTO dto : holidays) {
            if (isNationalHoliday(dto)) {
                national.add(dto);
            }
        }
        return national;
    }

   
    /**
     * @Purpose		: To check whether a holiday is a national or public holiday, based on its type and primary type.
     * @Param		: Holiday record to be checked (dto)
     **/
    private static Boolean isNationalHoliday(PublicHolidayInfoDTO dto) {
        if (dto == null) {
            return false;
        }
        String types = dto.holidayCategory == null ? '' : dto.holidayCategory.toLowerCase();
        String primary = dto.holidayPrimaryType == null ? '' : dto.holidayPrimaryType.toLowerCase();
        return types.contains('national holiday')
            || primary.contains('national holiday')
            || primary.contains('public holiday');
    }

    
    /**
     * @Purpose		: To trim the response body to the first 1000 characters so that a large payload is not written to the log.
     * @Param		: Response body received from the Calendarific API (body)
     **/
    private static String preview(String body) {
        if (String.isBlank(body)) {
            return body;
        }
        return body.length() <= 1000
            ? body
            : body.left(1000) + '... [truncated, ' + body.length() + ' chars]';
    }  
   
    /**
     * @Purpose		: To match the HTTP status code returned by the Calendarific API and return the matching user friendly message.
     * @Param		: HTTP status code returned by the Calendarific API (code)
     **/
    private static String userMessageForHttp(Integer code) {
        if (code == 401 || code == 403) {
            return 'We were able to validate your ID Number, but we could not retrieve the public holiday information at this time. Please try again later.';
        }
        if (code == 429) {
            return 'Holiday information is temporarily busy. Please try again later.';
        }
        if (code == 404 || code == 400 || code == 422) {
            return 'Holiday information is not available for this birth year.';
        }
        // 5xx and anything unmapped.
        return 'We were able to validate your ID Number, but we could not retrieve the public holiday information at this time. Please try again later.';
    }
    
}