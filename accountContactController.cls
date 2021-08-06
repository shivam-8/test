public with sharing class accountContactController {
    public accountContactController() {

    }
    @AuraEnabled(cacheable=true)
    public static List<Contact> getAccount(String accountId) {
        return [SELECT Id,FirstName, LastName FROM Contact WHERE AccountId=: accountId];
    } 
}