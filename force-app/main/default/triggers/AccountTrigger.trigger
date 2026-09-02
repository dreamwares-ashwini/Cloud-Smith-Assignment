trigger AccountTrigger on Account (after update) {
    if(Trigger.isAfter && Trigger.isUpdate){
        AccountTiggerHandler.handleAfterUpdate(Trigger.new,Trigger.oldMap);
    }

}