public class AAdemo {

    @AuraEnabled
    public static decimal calculate(decimal f ,decimal s){
        decimal res = f+s;
        return res;
    }

    @AuraEnabled(cacheable=true)
    public static List<string> getObject(){
        try {
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getContactFields(){
        SObjectType contactType = Schema.getGlobalDescribe().get('Contact');
        Map<String,Schema.SObjectField> mfields = contactType.getDescribe().fields.getMap();

        List<String> sObjectDetailsList = new List<String>();
        for(String s : mfields.keySet()){
            sObjectDetailsList.add(String.valueOf(mfields.get(s)));
        }
        return sObjectDetailsList;
    }
}public class AAdemo {

    @AuraEnabled
    public static decimal calculate(decimal f ,decimal s){
        decimal res = f+s;
        return res;
    }

    @AuraEnabled(cacheable=true)
    public static List<string> getObject(){
        try {
            
        } catch (Exception e) {
            throw new AuraHandledException(e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<String> getContactFields(){
        SObjectType contactType = Schema.getGlobalDescribe().get('Contact');
        Map<String,Schema.SObjectField> mfields = contactType.getDescribe().fields.getMap();

        List<String> sObjectDetailsList = new List<String>();
        for(String s : mfields.keySet()){
            sObjectDetailsList.add(String.valueOf(mfields.get(s)));
        }
        return sObjectDetailsList;
    }
}