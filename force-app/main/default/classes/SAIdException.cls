/**
 * @Class Name  : SAIdException
 * @Author      : Dreamwares
 * @CreateDate  : 27-08-2026
 * @Purpose     : To return the exception classes
 */
public with sharing class SAIdException extends Exception {
   
    public String userMessage { get; private set; }   
    public String errorCode { get; private set; }
    public SAIdException(String errorCode, String userMessage) {
        this.errorCode = errorCode;
        this.userMessage = userMessage;       
        this.setMessage(userMessage);
    }
}