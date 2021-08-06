public class AAFirstClass {
//   public static List<Integer> str=new List<Integer>();
    @AuraEnabled(cacheable=true)
    public static List<Account> firstMethod()
    {
        return [SELECT Id,Name,Website FROM Account];
        
    }
        
}