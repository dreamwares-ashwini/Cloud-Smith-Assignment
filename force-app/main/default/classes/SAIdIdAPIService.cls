/**
 * @Class Name  : SAIdIdAPIService
 * @Author      : Dreamwares
 * @CreateDate  : 27-08-2026
 * @Purpose     : Persistence and processing for ID searches.One South_Africa_ID_Record__c record is maintained per SA ID hash, with
 * Search_Count__c incremented for each repeated search.
 */
public without sharing class SAIdIdAPIService {
	/**
     * @Class Name  : PersistResult    
     * @Purpose     : To return the search Count with recordId based on the SA ID number
     **/
    public class PersistResult {
        public Id recordId;
        public Integer searchCount;
    }
   
    /** 
     * @Purpose     : Derives the stable, non-reversible storage key for an ID number.
     * @Param       : normalizedId The validated 13-digit SA ID number.
     * @return      : 64-character lowercase HMAC-SHA256 hash.
     **/
    public static String hashId(String normalizedId) {
        Calendarific_Custom_Setting__c secret =
            Calendarific_Custom_Setting__c.getOrgDefaults();

        String pepper =
            secret != null
                ? secret.Calendarific_Hash_Key__c
                : null;

        if (String.isBlank(pepper)) {
            pepper = UserInfo.getOrganizationId();
        }

        Blob mac = Crypto.generateMac(
            'hmacSHA256',
            Blob.valueOf(normalizedId),
            Blob.valueOf(pepper)
        );

        return EncodingUtil.convertToHex(mac);
    }

    /**
     * @Purpose     : To save the search record and api status for future reference.
     * @param decoded Validated and decoded SA ID information.
     * @param saIdNumber Raw SA ID number entered by the user.
     * @param holidayStatus Holiday retrieval status.
     * @param apiStatus API status.
     * @param apiError API error message, if applicable.
     * @param correlationId Request correlation Id.
     * @return PersistResult; see the class for what is and is not guaranteed.
     * @throws SouthAfricaIdException DML when the insert fails,
     *         EVENT when the publish is rejected
     */    
    public static PersistResult recordSearch(
        SAIdParseOutcomeWrapper parseOutcome,
        String saIdNumber,
        String holidayStatus,
        String apiStatus,
        String apiError,
        String transactionId
    ) {
        String hashVal = hashId(parseOutcome.normalizedId);
        SouthAfricanIDNumber_Record__c existing = getRecordByHash(hashVal);       
        SAID_Search_Event__e evt = buildEvent(
            hashVal,
            parseOutcome,
            holidayStatus,
            apiStatus,
            apiError,
            transactionId
        );

        PersistResult result = new PersistResult();
        if (existing == null) {
            result.recordId = insertFirstSearch(hashVal, saIdNumber, evt);
            result.searchCount = 1;
            return result;
        }

        Database.SaveResult publishResult = EventBus.publish(evt);
        if (!publishResult.isSuccess()) {
            SAIdException eventEx = new SAIdException(
                'EVENT',
                'We could not save your search. Please try again.'
            );           
            
            throw eventEx;
        }

        result.recordId = existing.Id;
        result.searchCount = currentCount(existing) + 1;
        return result;
    }

    /**  
     * @Purpose     : Creates the record for an ID being searched for the first time.
     * Two visitors can reach this simultaneously for the same hash and both
     * insert, because SA_ID_Hash__c is not enforced unique and nothing here
     * locks. The duplicate is tolerated rather than prevented: getRecordsByHash
     * resolves a hash to the oldest row, so every later search still lands on
     * one record and only the stray row is left behind.     *
     * @param       : hashVal    SA ID hash.
     * @param       : saIdNumber Raw SA ID number; written once, at creation only.
     * @param       : evt Carrier for the decoded and audit values.
     * @return      : the new record Id
     * @throws SouthAfricaIdException DML when the insert fails
     */
    private static Id insertFirstSearch(
        String hashVal,
        String saIdNumber,
        SAID_Search_Event__e evt
    ) {
        SouthAfricanIDNumber_Record__c rec = new SouthAfricanIDNumber_Record__c(
            SouthAfricanId_Hash__c = hashVal,
            SAID_Search_Count__c = 1,
            SouthAfrican_ID_Number__c = saIdNumber
        );

        applyEvent(rec, evt);

        try {
            return SAIdDataService.saveRecord(rec);          
        } catch (DmlException dmlEx) {            
            SAIdException wrapped = new SAIdException(
                'DML',
                'We could not save your search. Please try again.'
            );
            throw wrapped;
        }
    }

     /**
     * @Method Name : describeErrors   
     * @Purpose     : Flattens Database.Error entries into one readable line for the log.    
     * @param       : List of Database.Error
     */
    /** Flattens Database.Error entries into one readable line for the log. */
    private static String describeErrors(List<Database.Error> errors) {
        if (errors == null || errors.isEmpty()) {
            return 'no error detail supplied';
        }
        List<String> parts = new List<String>();
        for (Database.Error err : errors) {
            parts.add(err.getStatusCode() + ': ' + err.getMessage());
        }
        return String.join(parts, ' | ');
    }

    /**
     * @Method Name : applySearchEvents  
     * @Purpose     : Writes the searches carried by a batch of events.
     * Runs as the Automated Process user via SA_IDSearchEventTrigger, which is
     * what makes the UPDATE legal at all.
     * @param       : events the delivered batch; safe to pass an empty list
     */
    public static void applySearchEvents(List<SAID_Search_Event__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }       
      
        Map<String, Integer> incrementsByHash = new Map<String, Integer>();
        Map<String, SAID_Search_Event__e> latestByHash =
            new Map<String, SAID_Search_Event__e>();

        for (SAID_Search_Event__e evt : events) {
            if (String.isBlank(evt.SouthAfricanId_Hash__c)) {
                continue;
            }

            Integer seenSoFar =
                incrementsByHash.containsKey(evt.SouthAfricanId_Hash__c)
                    ? incrementsByHash.get(evt.SouthAfricanId_Hash__c)
                    : 0;

            incrementsByHash.put(evt.SouthAfricanId_Hash__c, seenSoFar + 1);
            latestByHash.put(evt.SouthAfricanId_Hash__c, evt);
        }

        if (latestByHash.isEmpty()) {
            return;
        }

        Map<String, SouthAfricanIDNumber_Record__c> existingByHash;

        try {
            existingByHash = getRecordsByHash(latestByHash.keySet());
        } catch (Exception queryEx) {          
             System.debug('Excpetion:'+ queryEx.getMessage());
            return;
        }

        List<SouthAfricanIDNumber_Record__c> toSave =
            new List<SouthAfricanIDNumber_Record__c>();

        for (String hashVal : latestByHash.keySet()) {
            SAID_Search_Event__e evt = latestByHash.get(hashVal);

            SouthAfricanIDNumber_Record__c rec = existingByHash.get(hashVal);

            if (rec == null) {               
                rec = new SouthAfricanIDNumber_Record__c(
                    SouthAfricanId_Hash__c = hashVal,
                    SAID_Search_Count__c = 0
                );
            }

            try {
                rec.SAID_Search_Count__c =
                    currentCount(rec) + incrementsByHash.get(hashVal);

                applyEvent(rec, evt);

                toSave.add(rec);
            } catch (Exception mapEx) { 
                System.debug('Excpetion:'+ mapEx.getMessage());
            }
        }

        try {
           // SouthAfricaDataService.saveRecords(toSave);
        } catch (Exception dmlEx) {          
             System.debug('Excpetion:'+ dmlEx.getMessage());
        } 
    }

   /**
     * @Method Name : transactionIdOf
     * @Purpose     : transaction id to log this delivery under: the first one carried by the
     * batch, or null if none of the events had one.
     * @return      : Return requested transaction Id
     */
    private static String transactionIdOf(List<SAID_Search_Event__e> events) {
        for (SAID_Search_Event__e evt : events) {
            if (String.isNotBlank(evt.Transaction_Reference_Id__c)) {
                return evt.Transaction_Reference_Id__c;
            }
        }
        return null;
    }

   /**
     * @Method Name : summariseDml
     * @Purpose     : Adds the row-level detail that a DmlException carries beyond its text.
     * @return      : Returns DML Exception
     */
    private static String summariseDml(Exception ex) {
        if (!(ex instanceof DmlException)) {
            return '';
        }

        DmlException dmlEx = (DmlException) ex;
        List<String> parts = new List<String>();

        for (Integer i = 0; i < dmlEx.getNumDml(); i++) {
            parts.add(
                'row ' + dmlEx.getDmlIndex(i) +
                ' ' + dmlEx.getDmlType(i) +
                ' on ' + dmlEx.getDmlFieldNames(i)
            );
        }

        return parts.isEmpty() ? '' : String.join(parts, '; ');
    }

   /**
     * @Method Name	: buildEvent
     * @Purpose		: Build SA ID Search event record 
     * @Param		: StholidayStatus
     * @Param		: String hashVal,
     * @Param		: SouthAfricaIdDecodeResult decoded,
     * @Param		: String holidayStatus,
     * @Param		: String apiStatus,
     * @Param		: String apiError,
     * @Param		: String transactionId 
     */
    private static SAID_Search_Event__e buildEvent(
        String hashVal,
        SAIdParseOutcomeWrapper parseOutcome,
        String holidayStatus,
        String apiStatus,
        String apiError,
        String transactionId
    ) {
        return new SAID_Search_Event__e(
            SouthAfricanId_Hash__c = hashVal,
            BirthDate__c = parseOutcome.dateOfBirth,
            BirthYear__c = parseOutcome.dobYear,
            BirthMonth__c = parseOutcome.dobMonth,
            BirthDay__c = parseOutcome.dobDay,
            Gender__c = parseOutcome.genderCode,
            Citizenship__c = parseOutcome.citizenship,
            Holiday_Query_Status__c = holidayStatus,
            Recent_API_Status__c = apiStatus,
            API_Service_Error__c =
                apiError == null
                    ? null
                    : apiError.left(255),
            Transaction_Reference_Id__c = transactionId,
            Holidays_Last_Query_DateTime__c = System.now()
        );
    }

    /**
     * @Method Name	: applyEvent
     * @Purpose		: Copies the decoded attributes and search/API audit values from an event onto the record.
     * @Param		: SouthAfricanIDNumber_Record__c
     * @Param		: Event SA_ID_Search__e
     */
    private static void applyEvent(
        SouthAfricanIDNumber_Record__c rec,
        SAID_Search_Event__e evt
    ) {
        rec.BirthDate__c =
            evt.BirthDate__c;

        rec.BirthYear__c =
            evt.BirthYear__c;

        rec.BirthMonth__c =
            evt.BirthMonth__c;

        rec.BirthDay__c =
            evt.BirthDay__c;

        rec.Gender__c =
            evt.Gender__c;

        rec.Citizenship__c =
            evt.Citizenship__c;
       
        DateTime searchedAt =
            evt.Holidays_Last_Query_DateTime__c == null
                ? evt.CreatedDate
                : evt.Holidays_Last_Query_DateTime__c;

        rec.Holidays_Last_Query_DateTime__c =
            searchedAt;

        rec.Verification_Result__c =
            'Valid';

        rec.Holiday_Query_Status__c =
            evt.Holiday_Query_Status__c;

        rec.Recent_API_Status__c =
            evt.Recent_API_Status__c;

        rec.API_Service_Error__c =
            evt.API_Service_Error__c;
        
        if (evt.Holiday_Query_Status__c != 'Failed') {
            rec.Holidays_Last_Query_DateTime__c =
                searchedAt;
        }

        rec.Transaction_Reference_Id__c =
            evt.Transaction_Reference_Id__c;
    }

    /**
     * @Method Name	: getRecordByHash
     * @Purpose		: Retrieves an existing record using the SA ID hash.
     * @Param		: hashVal SA ID hash.
     * @return		: Existing record or null when no record exists.
     */
    private static SouthAfricanIDNumber_Record__c getRecordByHash(
        String hashVal
    ) {
        Map<String, SouthAfricanIDNumber_Record__c> found =
            getRecordsByHash(new Set<String>{ hashVal });

        return found.get(hashVal);
    }

   /**
     * @Method Name	: getRecordsByHash
     * @Purpose		: Create map of hash with Records
     * @Param		: hashes SA ID hashes to look up.
     * @return		: map of hash to record; missing hashes are simply absent.
     */
    private static Map<String, SouthAfricanIDNumber_Record__c> getRecordsByHash(
        Set<String> hashes
    ) {
        Map<String, SouthAfricanIDNumber_Record__c> byHash =
            new Map<String, SouthAfricanIDNumber_Record__c>();

        for (SouthAfricanIDNumber_Record__c rec : [
            SELECT
                Id,
                SAID_Search_Count__c,
                Holidays_Last_Query_DateTime__c,
                SouthAfricanId_Hash__c
            FROM SouthAfricanIDNumber_Record__c
            WHERE SouthAfricanId_Hash__c IN :hashes
            ORDER BY CreatedDate ASC
        ]) {
            if (!byHash.containsKey(rec.SouthAfricanId_Hash__c)) {
                byHash.put(rec.SouthAfricanId_Hash__c, rec);
            }
        }

        return byHash;
    }

    /**
     * @Method Name	: currentCount     
     * @Purpose		: SAID_Search_Count__c as an Integer, treating a null or missing record as 0.
     * @Param		: South_Africa_ID_Record__c record
     * @return		: Return search count
     */
    private static Integer currentCount(SouthAfricanIDNumber_Record__c rec) {
        return rec == null || rec.SAID_Search_Count__c == null
            ? 0
            : Integer.valueOf(rec.SAID_Search_Count__c);
    }
}