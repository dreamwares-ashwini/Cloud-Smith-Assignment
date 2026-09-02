/**
 * @Class Name	: SAIdDecoder
 * @Author		: Dreamwares
 * @CreateDate	: 27-08-2026
 * @Purpose		: Validates and decodes a 13-digit South African national ID number.
 * Layout of the number, YYMMDDSSSSCAZ:
 *   1-2   YY    year of birth, two digits (century is inferred, see below)
 *   3-4   MM    month of birth
 *   5-6   DD    day of birth
 *   7-10  SSSS  gender sequence: 0000-4999 female, 5000-9999 male
 *   11    C     citizenship: 0 = SA citizen, 1 = permanent resident
 *   12    A     historically a race classification digit; obsolete and ignored
 *   13    Z     Luhn check digit over the first twelve 
 */
public without sharing class SAIdDecoder {    
    @TestVisible private static Date todayOverride;

    /**
     * @Purpose		: Runs every validation rule in turn and, on success, decodes the number.
     * @Param		: idNumber raw user input; leading and trailing whitespace is tolerated
     * @return		: a result whose isValid flag says whether the decoded members are
     *         populated; never null
     **/
    public static SAIdParseOutcomeWrapper validateAndDecode(String idNumber) {
        SAIdParseOutcomeWrapper result = new SAIdParseOutcomeWrapper();
        result.isValidResult = false;

        if (String.isBlank(idNumber)) {
            return fail(result, 'BLANK', 'Please enter a South African ID Number.');
        }      
        String normalized = idNumber.trim();
        if (!Pattern.matches('^[0-9]+$', normalized)) {
            return fail(result, 'NON_NUMERIC', 'The ID Number must contain digits only.');
        }
        if (normalized.length() != 13) {
            return fail(result, 'LENGTH', 'The ID Number must be exactly 13 digits.');
        }
        Integer yy = Integer.valueOf(normalized.substring(0, 2));
        Integer mm = Integer.valueOf(normalized.substring(2, 4));
        Integer dd = Integer.valueOf(normalized.substring(4, 6));
        Integer ssss = Integer.valueOf(normalized.substring(6, 10));
        String citizenshipDigit = normalized.substring(10, 11);
        Integer providedCheck = Integer.valueOf(normalized.substring(12, 13));

        if (mm < 1 || mm > 12) {
            return fail(result, 'MONTH', 'The ID Number contains an invalid month.');
        }
        if (dd < 1 || dd > 31) {
            return fail(result, 'DAY', 'The ID Number contains an invalid day.');
        }

        Date dob = resolveDateOfBirth(yy, mm, dd);
        if (dob == null) {
            return fail(result, 'DATE', 'The ID Number contains an invalid date of birth.');
        }

        if (citizenshipDigit != '0' && citizenshipDigit != '1') {
            return fail(result, 'CITIZENSHIP', 'The ID Number contains an invalid citizenship digit.');
        }
        
        Integer expectedCheck = computeCheckDigit(normalized.substring(0, 12));
        if (expectedCheck != providedCheck) {
            return fail(result, 'CHECKSUM', 'Please enter a valid South African ID Number.');
        }

        result.isValidResult = true;
        result.normalizedId = normalized;
        result.dateOfBirth = dob;
        result.dobYear = dob.year();
        result.dobMonth = dob.month();
        result.dobDay = dob.day();
        result.genderCode = ssss <= 4999 ? 'Female' : 'Male';
        result.citizenship = citizenshipDigit == '0'
            ? 'SA Citizen'
            : 'Permanent Resident';
        return result;
    }

    /**
     * @Purpose		: 
     * Resolves the two-digit year to a real date by inferring the century.     *
     * The ID number carries no century, so the rule is: prefer the 2000s
     * reading when it is not in the future, otherwise fall back to the 1900s.
     * For yy = 90 in 2026 that gives 1990, since 2090 is still ahead of us;
     * for yy = 05 it gives 2005.
     * Known limitation: anyone aged 100 or more is decoded a century too young,
     * because their 2000s reading is also a valid past date. The number alone
     * cannot disambiguate this.
     * @Param 		: Year, Month and Day
     * @return		: The resolved date, or null if YY/MM/DD is not a real calendar date
     */
    private static Date resolveDateOfBirth(Integer yy, Integer mm, Integer dd) {
        Date today = todayOverride != null ? todayOverride : Date.today();
        Date as20 = newDate(2000 + yy, mm, dd);
        if (as20 != null && as20 <= today) {
            return as20;
        }
        return newDate(1900 + yy, mm, dd);
    }

     /**
     * @Purpose		: Return the date
     * @Param		: Year, Month and Day
     * @return		: New instance of the date based on the input parameters.
     **/
    private static Date newDate(Integer year, Integer month, Integer day) {
        try {
            Date d = Date.newInstance(year, month, day);
            if (d.year() != year || d.month() != month || d.day() != day) {
                return null;
            }
            return d;
        } catch (Exception e) {
            return null;
        }
    }

    /**
     * @Purpose		: Computes the check digit using the Luhn variant implementation.
     * @param firstTwelve the first twelve digits, already known to be numeric.
     */
    @TestVisible
    static Integer computeCheckDigit(String firstTwelve) {
        Integer oddSum = 0;
        for (Integer i = 0; i < 12; i += 2) {
            oddSum += Integer.valueOf(firstTwelve.substring(i, i + 1));
        }
        String evenConcat = '';
        for (Integer i = 1; i < 12; i += 2) {
            evenConcat += firstTwelve.substring(i, i + 1);
        }       
        Integer evenProduct = Integer.valueOf(evenConcat) * 2;
        Integer evenDigitSum = 0;
        String evenAsText = String.valueOf(evenProduct);
        for (Integer i = 0; i < evenAsText.length(); i++) {
            evenDigitSum += Integer.valueOf(evenAsText.substring(i, i + 1));
        }
        Integer total = oddSum + evenDigitSum;
        return Math.mod(10 - Math.mod(total, 10), 10);
    }

    /**
     * Stamps a failure onto the result and hands it straight back, which keeps
     * each validation rule above to a single-line early return.
     */
    private static SAIdParseOutcomeWrapper fail(
        SAIdParseOutcomeWrapper result,
        String code,
        String message
    ) {
        result.errorCode = code;
        result.errorMessage = message;
        return result;
    }
}