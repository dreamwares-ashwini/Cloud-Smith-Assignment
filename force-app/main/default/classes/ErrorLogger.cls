/**
 * @Class Name      : ErrorLogger
 * @Author          : Dreamwares
 * @Purpose         : Generic utility class for logging Apex
 *                    exceptions into Error_Log__c.
 *  Example: System.NullPointerException, System.CalloutException, System.DmlException
 */
public without sharing class ErrorLogger {

    /**
     * Log an Apex exception.
     *
     * @param	:ex Apex exception.
     * @param	:sourceClass  Name of the Apex class where the exception occurred.
     * @param	:sourceMethod Name of the method where the exception occurred.
     * @param	:transactionReferenceId Unique transaction/request reference ID.
     */
    public static void logException(
        Exception ex,
        String sourceClass,
        String sourceMethod,
        String transactionReferenceId
    ) {
        if (ex == null) {
            return;
        }
        try {
            Error_Log__c errorLog = new Error_Log__c();
            errorLog.Error_Message__c = ex.getMessage();
            errorLog.Error_Type__c = ex.getTypeName();
            errorLog.Line_Number__c = ex.getLineNumber();
            errorLog.Source_Class__c = sourceClass;
            errorLog.Source_Method__c = sourceMethod;
            errorLog.Stack_Trace__c = ex.getStackTraceString();
            errorLog.Transaction_Reference_Id__c = transactionReferenceId;

            Database.SaveResult result =
                Database.insert(
                    errorLog,
                    false
                );


            if (!result.isSuccess()) {

                for (
                    Database.Error error :
                    result.getErrors()
                ) {

                    System.debug(
                        LoggingLevel.ERROR,
                        '# Error Log Insert Failed: ' +
                        error.getStatusCode() +
                        ' - ' +
                        error.getMessage()
                    );
                }
            }

        } catch (Exception loggingException) {
            System.debug(
                LoggingLevel.ERROR,
                '# ErrorLogger Exception: ' +
                loggingException.getMessage()
            );
        }
    }
}