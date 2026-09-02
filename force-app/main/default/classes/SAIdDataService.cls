/**
 * @Class Name  : SouthAfricaDataService
 * @Author      : Dreamwares
 * @CreateDate  : 19-08-2026
 * @Purpose     : This is utility class use to handles the DML operation
 */
public without sharing class SAIdDataService {

    /**
     * @Method Name : insertRecord    
     * @Purpose     : Inserts a new South Africa ID record.
     * @param		: recordToInsert Record to insert
     * @return		: The inserted record Id
     */
    public static Id insertRecord(
        SouthAfricanIDNumber_Record__c recordToInsert
    ) {
        insert recordToInsert;
        return recordToInsert.Id;
    }

    /**
     * @Method Name : updateRecord    
     * @Purpose     : Updates an existing South Africa ID record.
     * @param		: recordToUpdate Record to update
     * @return		: The updated record Id
     */
    public static Id updateRecord(
        SouthAfricanIDNumber_Record__c recordToUpdate
    ) {
        update recordToUpdate;
        return recordToUpdate.Id;
    }

    /**
     * @Method Name : saveRecord    
     * @Purpose     : Inserts or updates a record depending on whether an Id exists.   
     * Keeping this decision here avoids repeated DML logic in callers.
     * @param		: recordToSave Record to persist
     * @return		: The persisted record Id
     */
    public static Id saveRecord(
        SouthAfricanIDNumber_Record__c recordToSave
    ) {
        if (recordToSave == null) {
            throw new SAIdException(
                'DML',
                'Record cannot be null.'
            );
        }

        saveRecords(new List<SouthAfricanIDNumber_Record__c>{ recordToSave });

        return recordToSave.Id;
    }

    /**
     * @Method Name : saveRecords    
     * @Purpose     : To handle bulk record insert and upate the South_Africa_ID_Record__c
     * @param		: List of South_Africa_ID_Record__crecords to Save and to persist; null or empty is a no-op
     */
    public static void saveRecords(
        List<SouthAfricanIDNumber_Record__c> recordsToSave
    ) {
        if (recordsToSave == null || recordsToSave.isEmpty()) {
            return;
        }

        List<SouthAfricanIDNumber_Record__c> toInsert =
            new List<SouthAfricanIDNumber_Record__c>();

        List<SouthAfricanIDNumber_Record__c> toUpdate =
            new List<SouthAfricanIDNumber_Record__c>();

        for (SouthAfricanIDNumber_Record__c rec : recordsToSave) {
            if (rec == null) {
                continue;
            }

            if (rec.Id == null) {
                toInsert.add(rec);
            } else {
                toUpdate.add(rec);
            }
        }

        if (!toInsert.isEmpty()) {
            insert toInsert;
        }

        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }
}