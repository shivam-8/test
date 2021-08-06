/**
 * @Description        : Used to create BU Territory Contacts for Partner
 * Author              : Amol Sable
 * Ver       Date            Author      		    Modification
 * 1.0      19-08-2020       Amol Sable              Initial Version
 * 2.0      14-01-2021       Jayaraman Iyer          SVS-3175 Apex Class renaming
 * 3.0      20-01-2021       Chirag Lapasia          SVS-3173 - Resolved Duplicate Contacts creation bug
**/
public with sharing class SPMBUContactsController {

    // 3.0
    /**
    * Method Name : insertContactRecords
    * Description : Used to insert contact records.
    * Created By  : Chirag Lapasia
    **/
    @AuraEnabled
    public static primaryAndLegalContactResultWrapper insertContactRecords(
        String partnerAccId,
        Map<String, Map<String, String>> fieldNameValueMap,
        Id parentInstrumentationId,
        Map<String, Boolean> contactTypeCheckboxValueMap
    ) {
        String partnerContactRecordType;
        String acrRolePrimaryContact;
        String acrRoleLegal;
        IUnitOfWork unitOfWorkObj = UnitOfWork.newInstance(SPMBUContactsController.class);
        DateTime startTimestamp = DateTime.now();
        List<String> contactIdLst = new List<String>();
        String moduleValueText = '';
        primaryAndLegalContactResultWrapper primaryAndLegalContactResult = new primaryAndLegalContactResultWrapper();

        try {
            Schema.DescribeSObjectResult conDescribe = Schema.SObjectType.Contact;
            Map<String,Schema.RecordTypeInfo> contactRecordtypeByDevNameMap = conDescribe.getRecordTypeInfosByDeveloperName();

            // Fetch the GPP onboarding settings records
            Set<String> developerNameSet = new Set<String>{
                'PartnerContactRecordType',
                'ACRRolePrimaryContact',
                'ACRRoleLegal'
            };

            GPPOnboardingSettings__mdt[] gppOnboardingSettingsList =
            SPMQuerySelector.getInstance().getGPPOnboardingSettingData(developerNameSet);

            for(GPPOnboardingSettings__mdt gppOnboardingSetting : gppOnboardingSettingsList) {
                if (
                    gppOnboardingSetting.DeveloperName == 'PartnerContactRecordType' &&
                    contactRecordtypeByDevNameMap.containsKey(gppOnboardingSetting.Value__c)
                ) {
                    partnerContactRecordType = contactRecordtypeByDevNameMap.get(gppOnboardingSetting.Value__c).getRecordTypeId();
                }
                if (gppOnboardingSetting.DeveloperName == 'ACRRolePrimaryContact') {
                    acrRolePrimaryContact = gppOnboardingSetting.Value__c;
                }
                if (gppOnboardingSetting.DeveloperName == 'ACRRoleLegal') {
                    acrRoleLegal = gppOnboardingSetting.Value__c;
                }
            }

            if (!fieldNameValueMap.isEmpty()) {
                Map<String, String> contactTypeVsContactIdMap = new Map<String, String>();
                Map<String, Contact> contactMap = new Map<String, Contact>();
                Map<String, Contact> contactsToInsertMap = new Map<String, Contact>();
                Map<String, Set<String>> contactIdVsContactTypeMap = new  Map<String, Set<String>>();
                List<AccountContactRelation> accountContactRelationToInsert = new List<AccountContactRelation>();
                Set<String> setOldContactIds = new Set<String>();

                // $
                Set<String> allContactIdSet = new Set<String>();
                Set<String> ACRNotToBeDeletedSet = new Set<String>();
                Set<String> contactNotToBeDeletedSet = new Set<String>();

                // Delete existing Contact records so that it can be created below as per latest updates
                List<Contact> contactListToDelete = SPMQuerySelector.getInstance().getContactsByAccount(partnerAccId);
                if (contactListToDelete.isEmpty() == false) {

                    // $
                    for (Contact contact : contactListToDelete) {
                        allContactIdSet.add(contact.Id);
                    }

                    List<AccountContactRelation> presentACRList =
                        SPMQuerySelector.getInstance().getAccountContactRelationByAccount(allContactIdSet);

                    for (AccountContactRelation presentACR : presentACRList) {
                        if (presentACR.AccountId != partnerAccId) {
                            contactNotToBeDeletedSet.add(presentACR.ContactId);
                        }
                    }

                    List<Contact> contactListToBeDeleted = new List<Contact>();
                    for (Contact contact : contactListToDelete) {
                        if (!contactNotToBeDeletedSet.contains(contact.Id)) {
                            contactListToBeDeleted.add(contact);
                        }
                    }
                    // $
                    unitOfWorkObj.registerDeleted(contactListToBeDeleted);
                    unitOfWorkObj.save();
                    unitOfWorkObj.clear();
                    String contactDeletedIds = '';
                    for (Contact contact : contactListToBeDeleted) {
                        if (String.isBlank(contactDeletedIds)) {
                            contactDeletedIds = contact.Id;
                        } else {
                            contactDeletedIds = contactDeletedIds + ','+contact.Id;
                        }
                        setOldContactIds.add(contact.Id);
                    }
                    moduleValueText += 'Previously created Contacts are now deleted: ' + contactDeletedIds;
                }

                // Delete existing ACR so that it can be created as per latest updates
                List<AccountContactRelation> accountContactRelationList =
                    SPMQuerySelector.getInstance().getAllContactsData(partnerAccId);
                if (!accountContactRelationList.isEmpty()) {

                    // $
                    List<AccountContactRelation> acrListToBeDeleted = new List<AccountContactRelation>();
                    List<AccountContactRelation> acrListToBeUpdatedWithEmptyRoles = new List<AccountContactRelation>();
                    for (AccountContactRelation accountContactRelationInstance : accountContactRelationList) {
                        if (!contactNotToBeDeletedSet.contains(accountContactRelationInstance.ContactId)) {
                            acrListToBeDeleted.add(accountContactRelationInstance);
                        } else {
                            accountContactRelationInstance.Roles = '';
                            acrListToBeUpdatedWithEmptyRoles.add(accountContactRelationInstance);
                            ACRNotToBeDeletedSet.add(accountContactRelationInstance.Id);
                        }
                    }
                    // $

                    if (acrListToBeDeleted.isEmpty() == false) {
                        unitOfWorkObj.registerDeleted(acrListToBeDeleted);
                        unitOfWorkObj.save();
                        unitOfWorkObj.clear();
                        String accountContactRelationDeletedIds = '';
                        for (AccountContactRelation objAccountContactRelation : acrListToBeDeleted) {
                            if (String.isBlank(accountContactRelationDeletedIds)) {
                                accountContactRelationDeletedIds = objAccountContactRelation.Id;
                            } else {
                                accountContactRelationDeletedIds = accountContactRelationDeletedIds + ','+objAccountContactRelation.Id;
                            }
                        }
                        moduleValueText += ';Previously created ACR is now deleted: ' + accountContactRelationDeletedIds;
                    }

                    // $
                    if (acrListToBeUpdatedWithEmptyRoles.isEmpty() == false) {
                        unitOfWorkObj.registerChanged(acrListToBeUpdatedWithEmptyRoles);
                        unitOfWorkObj.save();
                        unitOfWorkObj.clear();
                        String accountContactRelationUpdatedIds = '';
                        for (AccountContactRelation objAccountContactRelation : acrListToBeUpdatedWithEmptyRoles) {
                            if (String.isBlank(accountContactRelationDeletedIds)) {
                                accountContactRelationUpdatedIds = objAccountContactRelation.Id;
                            } else {
                                accountContactRelationUpdatedIds = accountContactRelationUpdatedIds + ','+objAccountContactRelation.Id;
                            }
                        }
                        moduleValueText += ';Previously created ACR is now updated with empty role: ' + accountContactRelationUpdatedIds;
                    }
                }

                // Fill the collection which is used to insert Contact records
                for (String contactType : fieldNameValueMap.keySet()) {
                    Contact contactRecord = new Contact();
                    for (String fieldName : fieldNameValueMap.get(contactType).keySet()) {
                        if (
                            fieldNameValueMap.get(contactType).containskey('Id') &&
                            !setOldContactIds.contains(fieldNameValueMap.get(contactType).get('Id')) &&
                            !contactNotToBeDeletedSet.contains(fieldNameValueMap.get(contactType).get('Id')) //$
                        ) {
                            contactTypeVsContactIdMap.put(
                                contactType,
                                fieldNameValueMap.get(contactType).get('Id')
                            );
                        }
                        if (
                            (fieldName != 'Id') ||
                            (fieldName == 'Id' && !setOldContactIds.contains(fieldNameValueMap.get(contactType).get('Id')) && !contactNotToBeDeletedSet.contains(fieldNameValueMap.get(contactType).get('Id'))) // $
                        ) {
                            contactRecord.put(fieldName, fieldNameValueMap.get(contactType).get(fieldName));
                        }
                    }
                    contactMap.put(contactType, contactRecord);
                    contactsToInsertMap.put(contactType, contactRecord);
                }

                // Check if the Contact is associated in another Account. If yes, then we dont need to create the Contact again
                // as it would be re-used due to result of Duplication modal or in cases where "Use Owner Signatory" checkbox
                // might have been checked
                if (contactTypeVsContactIdMap.isEmpty() == false) {

                    // Fetch the Contact records whose Id's are present
                    List<Contact> contactList = SPMQuerySelector.getInstance().getContactRecords(contactTypeVsContactIdMap.values());
                    for (Contact contact : contactList) {
                        if (contact.AccountId != partnerAccId) {
                            for (String typeOfContact : contactTypeVsContactIdMap.keySet()) {
                                if (contactTypeVsContactIdMap.get(typeOfContact) == contact.Id) {

                                    // Remove the Contact from Contact insertion list
                                    contactsToInsertMap.remove(typeOfContact);
                                    if (contactIdVsContactTypeMap.containsKey(contact.Id)) {
                                        contactIdVsContactTypeMap.get(contact.Id).add(typeOfContact);
                                    } else {
                                        contactIdVsContactTypeMap.put(contact.Id, new Set<String>{typeOfContact});
                                    }
                                    contactIdLst.add(contact.Id);
                                }
                            }
                        }
                    }
                }

                // Check if Either of "Use Owner Signatory" is checked for Primary Contact or
                // "Use Primary Contact" is checked for Legal Contact
                for (String typeOfContact : contactTypeCheckboxValueMap.keySet()) {
                    if (contactTypeCheckboxValueMap.get(typeOfContact) == true) {
                        String contactId = contactMap.get(typeOfContact).Id;

                        // Remove the Contact from Contact insertion list
                        contactsToInsertMap.remove(typeOfContact);
                        if (String.isNotBlank(contactId)) {
                            if (contactIdVsContactTypeMap.containsKey(contactId)) {
                                contactIdVsContactTypeMap.get(contactId).add(typeOfContact);
                            } else {
                                contactIdVsContactTypeMap.put(contactId, new Set<String>{typeOfContact});
                            }
                            contactIdLst.add(contactId);
                        }
                    }
                }

                // Insert the Contacts
                if (!contactsToInsertMap.isEmpty()) {
                    unitOfWorkObj.registerNewOrChanged(contactsToInsertMap.values());
                    unitOfWorkObj.save();
                    unitOfWorkObj.clear();

                    System.debug('194 contactsToInsertMap ::>> '+JSON.serialize(contactsToInsertMap));
 
                    if(contactsToInsertMap.containsKey('OwnerSignatory')){ 
                        primaryAndLegalContactResult.primaryContact = contactsToInsertMap.get('OwnerSignatory');
                    }

                    List<Id> contactIdList = new List<Id>();
                    contactIdList.addAll((new Map<Id, Contact>(contactsToInsertMap.values())).keyset());
                    contactIdLst = contactIdList;
                    moduleValueText += 'Contact Saved: ' + String.join(contactIdList, ',');

                    Map<String, Set<String>> contactIdWithTypeMap = new Map<String, Set<String>>();
                    for (String typeOfContact : contactsToInsertMap.keySet()) {
                        if (contactIdWithTypeMap.containsKey(contactsToInsertMap.get(typeOfContact).Id)) {
                            contactIdWithTypeMap.get(contactsToInsertMap.get(typeOfContact).Id).add(typeOfContact);
                        } else {
                            contactIdWithTypeMap.put(contactsToInsertMap.get(typeOfContact).Id, new Set<String>{typeOfContact});
                        }
                    }

                    // Explicitly create ACR when Legal Contact is dependent on primary Contact but Primary Contact
                    // Is inserted in current transaction
                    if (
                        contactTypeCheckboxValueMap.containsKey('LegalPrimaryContact') &&
                        contactTypeCheckboxValueMap.get('LegalPrimaryContact') == true
                    ) {
                        Boolean legalPrimaryContactPresent = false;
                        for (String contactId  : contactIdWithTypeMap.keySet()) {
                            if (contactIdWithTypeMap.get(contactId).contains('LegalPrimaryContact')) {
                                legalPrimaryContactPresent = true;
                                break;
                            }
                        }
                        if (!legalPrimaryContactPresent) {
                            for (String contactId : contactIdWithTypeMap.keySet()) {
                                if (contactIdWithTypeMap.get(contactId).contains('OwnerSignatory')) {
                                    contactIdWithTypeMap.get(contactId).add('LegalPrimaryContact');
                                }
                            }
                        }
                    }

                    // Fetch the ACR of the created Contacts so that their roles can be updated
                    List<AccountContactRelation> accountContactRelList =
                        SPMQuerySelector.getInstance().getAllContactsData(partnerAccId);

                    // Update the Roles of ACR
                    if (!accountContactRelList.isEmpty()) {
                        for (AccountContactRelation accountContactRelation : accountContactRelList) {
                            //$
                            List<AccountContactRelation> accountContactRelationToUpdate = new List<AccountContactRelation>();
                            if (!ACRNotToBeDeletedSet.contains(accountContactRelation.Id)) {
                                if (contactIdWithTypeMap.containsKey(accountContactRelation.ContactId)) {
                                    Set<String> contactTypesSet = contactIdWithTypeMap.get(accountContactRelation.ContactId);
                                    String roles = '';
                                    for (String typeOfContact : contactTypesSet) {
                                        if (String.isBlank(roles)) {
                                            roles = (typeOfContact == 'OwnerSignatory' ? acrRolePrimaryContact : acrRoleLegal);
                                        } else {
                                            roles = roles + ';' + (typeOfContact == 'OwnerSignatory' ? acrRolePrimaryContact : acrRoleLegal);
                                        }
                                    }
                                    accountContactRelation.Roles = roles;
                                    accountContactRelationToUpdate.add(accountContactRelation);
                                }
                            }
                        }
                        if (accountContactRelationToUpdate.isEmpty() == false) {
                            unitOfWorkObj.registerNewOrChanged(accountContactRelationToUpdate); // $
                            unitOfWorkObj.save();
                            unitOfWorkObj.clear();
                            List<Id> acrList = new List<Id>();
                            for (AccountContactRelation accountContactRelation : accountContactRelationToUpdate) { // $
                                acrList.add(accountContactRelation.Id);
                            }
                            if (String.isBlank(moduleValueText)) {
                                moduleValueText += 'AccountContactRelation Saved: ' + String.join(acrList, ',');
                            } else {
                                moduleValueText += ';AccountContactRelation Saved: ' + String.join(acrList, ',');
                            }
                        }
                    }
                }

                // Explicitly create ACR when the Existing Contacts are present from Different Accounts
                if (contactIdVsContactTypeMap.isEmpty() == false) {
                    for (String contactId : contactIdVsContactTypeMap.keySet()) {
                        AccountContactRelation accountContactRelation = new AccountContactRelation();
                        accountContactRelation.AccountId = partnerAccId;
                        accountContactRelation.ContactId = contactId;
                        String roles = '';
                        for (String typeOfContact : contactIdVsContactTypeMap.get(contactId)) {
                            if (String.isBlank(roles)) {
                                roles = (typeOfContact == 'OwnerSignatory' ? acrRolePrimaryContact : acrRoleLegal);
                            } else {
                                roles = roles + ';' + (typeOfContact == 'OwnerSignatory' ? acrRolePrimaryContact : acrRoleLegal);
                            }
                        }
                        accountContactRelation.Roles = roles;
                        accountContactRelationToInsert.add(accountContactRelation);
                    }
                    unitOfWorkObj.registerNewOrChanged(accountContactRelationToInsert);
                    unitOfWorkObj.save();
                    unitOfWorkObj.clear();
                    List<Id> acrList = new List<Id>();
                    for (AccountContactRelation accountContactRelation : accountContactRelationToInsert) {
                        acrList.add(accountContactRelation.Id);
                    }
                    if (String.isBlank(moduleValueText)) {
                        moduleValueText += 'AccountContactRelation Saved: ' + String.join(acrList, ',');
                    } else {
                        moduleValueText += ';AccountContactRelation Saved: ' + String.join(acrList, ',');
                    }
                }

                SPMOnboardController.getInstance().logInstrumentation(
                    parentInstrumentationId,
                    'BU Contacts',
                    SVSConstants.INSTRUMENTATION_STATUS_SUCCESS,
                    moduleValueText,
                    startTimestamp
                );
                defaultContactRole(partnerAccId, parentInstrumentationId);
            }
        }  catch(exception ex){
            SPMOnboardController.getInstance().logInstrumentation(
                parentInstrumentationId,
                'Contacts',
                SVSConstants.INSTRUMENTATION_STATUS_FAILURE,
                ex.getMessage().left(255),
                startTimestamp
            );
        }
        
        primaryAndLegalContactResult.newOrUpdatedContactIdList =  contactIdLst;
        return primaryAndLegalContactResult;
    }

    /**
    * Method Name : insertContactRecords
    * Description : Used to insert contact records. Commented as part of 3.0
    * Created By  : Amol Sable
    **/
    /*@AuraEnabled()
    public static List<Contact> insertContactRecords(String partnerAccId
        , Map<String, Map<String, String>> fieldNameValueMap
        , Boolean ownerSignatoryIsPrimary
        , Id parentInstrumentationId
        , Map<String, Boolean> contactTypeCheckboxValueMap){

        String partnerContactRecordType;
        //SVS-2493
        String acrRolePrimaryContact; 
        String acrRoleLegal;
        String accountStatusPending;
        Map<String, AccountContactRelation> acrRoleAndContactMap = new Map<String, AccountContactRelation>();
        Map<String, Boolean> contactLinkCheckMap = new Map<String, Boolean>();
        List<AccountContactRelation> existingAccountContactList = new List<AccountContactRelation>();
        //SVS-2493
        Set<String> contactEmailSet = new Set<String>();                                    
        Map<String, Contact> contactMap = new Map<String, Contact>();
        List<String> contactTypeList = new List<String>();
        Map<String, Contact> existingContactMap = new Map<String, Contact>();
        Map<Id, AccountContactRelation> contactToACRMap = new Map<Id, AccountContactRelation>();

        Schema.DescribeSObjectResult conDescribe = Schema.SObjectType.Contact; 
        Map<String,Schema.RecordTypeInfo> conRecordtypeByDevNameMap = conDescribe.getRecordTypeInfosByDeveloperName();
        Set<String> developerNameSet = new Set<String>{
            'PartnerContactRecordType',
            'ACRRolePrimaryContact',
            'ACRRoleLegal', 
            'AccountStatusPending'
        };

        GPPOnboardingSettings__mdt[] gppOnboardingSettingsList = SPMQuerySelector.getInstance().getGPPOnboardingSettingData(developerNameSet);
                                                        
        for(GPPOnboardingSettings__mdt gppOnboardingSetting : gppOnboardingSettingsList){
            if(gppOnboardingSetting.DeveloperName == 'PartnerContactRecordType' && conRecordtypeByDevNameMap.containsKey(gppOnboardingSetting.Value__c)){
                partnerContactRecordType = conRecordtypeByDevNameMap.get(gppOnboardingSetting.Value__c).getRecordTypeId();        
            }
            if(gppOnboardingSetting.DeveloperName == 'ACRRolePrimaryContact'){
                acrRolePrimaryContact = gppOnboardingSetting.Value__c;        
            }
            if(gppOnboardingSetting.DeveloperName == 'ACRRoleLegal'){
                acrRoleLegal = gppOnboardingSetting.Value__c;        
            }
            if(gppOnboardingSetting.DeveloperName == 'AccountStatusPending'){
                accountStatusPending = gppOnboardingSetting.Value__c;        
            } 
        }

        if (!fieldNameValueMap.isEmpty()) {
            
            IUnitOfWork unitOfWorkObj = UnitOfWork.newInstance(SPMBUContactsController.class);
            DateTime startTimestamp = DateTime.now();

            for(String contactType : fieldNameValueMap.keySet()) {
                Contact contactRecord = new Contact();
                for(String fieldName : fieldNameValueMap.get(contactType).keySet()) {
                    contactRecord.put(fieldName, fieldNameValueMap.get(contactType).get(fieldName));
                    if (fieldName == 'Email' && fieldNameValueMap.get(contactType).containskey('Id')) {
                        contactEmailSet.add(fieldNameValueMap.get(contactType).get(fieldName));
                    }
                }
                contactMap.put(contactType, contactRecord);    
                contactTypeList.add(contactType);  
            }
            List<Contact> contactList = SPMQuerySelector.getInstance().getExtingContactRecords(contactEmailSet, partnerContactRecordType);
            for(Contact contact : contactList){
                existingContactMap.put(contact.Email, contact);
            }
            
            Map<String, contact> contactTypeContactMap = new Map<String, contact>();
            for(String contactType : contactMap.keySet()) {
                contact contactRecord = contactMap.get(contactType);
                if (existingContactMap.containskey(contactRecord.Email)) {
                    //SVS-2338
                    contactTypeContactMap.put(contactType, existingContactMap.get(contactRecord.Email));
                    //SVS-2493
                    
                    if(!ownerSignatoryIsPrimary){
                        //contactMap.remove(contactType);
                        contactMap.get(contactType).AccountId = contactTypeContactMap.get(contactType).AccountId;
                    }
                    if(contactMap.get(contactType).Id == null){
                        contactMap.remove(contactType); 
                    }
                } else {
                    contactTypeContactMap.put(contactType, contactRecord);
                    existingContactMap.put(contactRecord.Email, contactRecord);
                } 
            }
            
            //SVS2493
            List<AccountContactRelation> accountContactRelList = SPMQuerySelector.getInstance().getAllContactsData(partnerAccId);
            
            if(accountContactRelList != null && accountContactRelList.size()>0){
                for(AccountContactRelation accConRelation: accountContactRelList){
                    
                    Boolean isDirectlyLinkedContact = true;
                    
                    if(accConRelation.Contact.AccountId != partnerAccId){
                        isDirectlyLinkedContact = false;
                    }
                    
                    if(isDirectlyLinkedContact && accConRelation.Account.Status__c == accountStatusPending
                    || (!isDirectlyLinkedContact && accConRelation.Contact.Account.Status__c == accountStatusPending)){
                        
                        if(accConRelation != null && accConRelation.Roles != null && accConRelation.Roles.contains(';')){
                            String[] rolesArray = accConRelation.Roles.split(';');
                            acrRoleAndContactMap.put(rolesArray[0], accConRelation);
                            acrRoleAndContactMap.put(rolesArray[1], accConRelation);
                            contactLinkCheckMap.put(rolesArray[0], isDirectlyLinkedContact);
                            contactLinkCheckMap.put(rolesArray[1], isDirectlyLinkedContact);
                            if(rolesArray.size()>2){
                               acrRoleAndContactMap.put(rolesArray[2], accConRelation);
                                contactLinkCheckMap.put(rolesArray[2], isDirectlyLinkedContact);
                            }
                        } else{
                            if(accConRelation != null && accConRelation.Roles != null){
                                
                                if(accConRelation.Roles == acrRolePrimaryContact){
                                    if(!isDirectlyLinkedContact && contactTypeContactMap.get('OwnerSignatory').Email == accConRelation.Contact.Email 
                                        && !ownerSignatoryIsPrimary){
                                        contactMap.get('OwnerSignatory').AccountId = accConRelation.Contact.AccountId;
                                    }
                                    //SVS-2676
                                    if(!contactTypeCheckboxValueMap.isEmpty() && contactTypeCheckboxValueMap.containsKey('OwnerSignatory') && contactTypeCheckboxValueMap.get('OwnerSignatory') != true && accConRelation.Roles != null){
                                    //if(accConRelation.Roles != null){  
                                        contactMap.get('OwnerSignatory').Id = accConRelation.ContactId;
                                    }
                                    if(contactTypeCheckboxValueMap.containsKey('OwnerSignatory') && contactTypeCheckboxValueMap.get('OwnerSignatory') == true && contactTypeContactMap.containsKey('OwnerSignatory') && contactTypeContactMap.get('OwnerSignatory').Email != accConRelation.Contact.Email){
                                        accConRelation.Roles = null;
                                        existingAccountContactList.add(accConRelation);
                                    }
                                        
                                } 
                                else if(accConRelation.Roles == acrRoleLegal){
                                    if(!isDirectlyLinkedContact && contactTypeContactMap.containsKey('LegalPrimaryContact') && contactTypeContactMap.get('LegalPrimaryContact').Email == accConRelation.Contact.Email){
                                        contactMap.get('LegalPrimaryContact').AccountId = accConRelation.Contact.AccountId;
                                    }
                                    if(contactMap.containskey('LegalPrimaryContact') && contactTypeCheckboxValueMap.containsKey('LegalPrimaryContact')){
                                        
                                        if(!contactTypeCheckboxValueMap.isEmpty() && contactTypeCheckboxValueMap.get('LegalPrimaryContact') != true && accConRelation.Roles != null){
                                            contactMap.get('LegalPrimaryContact').Id = accConRelation.ContactId;
                                        }
                                        if(contactTypeCheckboxValueMap.get('LegalPrimaryContact') == true && contactTypeContactMap.containsKey('LegalPrimaryContact') && contactTypeContactMap.get('LegalPrimaryContact').Email != accConRelation.Contact.Email){
                                            accConRelation.Roles = null;
                                            existingAccountContactList.add(accConRelation);
                                        }
                                        
                                    }
                                }
                            }
                        }
                    }
                }
                
                for(String roleType : acrRoleAndContactMap.keyset()){
                    Boolean isDirectlyLinked = contactLinkCheckMap.get(roleType);
                    
                    if(roleType == acrRolePrimaryContact){
                        
                        if(!isDirectlyLinked && contactTypeContactMap.containsKey('OwnerSignatory') && contactTypeContactMap.get('OwnerSignatory').Email == acrRoleAndContactMap.get(roleType).Contact.Email 
                        && !ownerSignatoryIsPrimary){
                            
                            contactMap.get('OwnerSignatory').AccountId = acrRoleAndContactMap.get(roleType).Contact.AccountId;
                        }
                        
                        //SVS-2676 added check
                        if((!isDirectlyLinked && contactMap.containskey('OwnerSignatory') && contactMap.get('OwnerSignatory').Email == acrRoleAndContactMap.get(roleType).Contact.Email)
                            || (isDirectlyLinked) && contactTypeCheckboxValueMap.containsKey('OwnerSignatory') && contactTypeCheckboxValueMap.get('OwnerSignatory') == true){
                            
                            contactMap.get('OwnerSignatory').Id = acrRoleAndContactMap.get(roleType).ContactId;
                        }
                        
                        else if(contactMap.containskey('OwnerSignatory') && acrRoleAndContactMap.get(roleType).Id == acrRoleAndContactMap.get(acrRolePrimaryContact).Id
                            && acrRoleAndContactMap.get(roleType).Contact.Email != contactMap.get('OwnerSignatory').Email){
                            
                            acrRoleAndContactMap.get(roleType).Roles = null;
                            existingAccountContactList.add(acrRoleAndContactMap.get(roleType));
                        } 
                        if(contactTypeCheckboxValueMap.get('OwnerSignatory') == true && contactMap.containskey('OwnerSignatory') && acrRoleAndContactMap.get(roleType).Id == acrRoleAndContactMap.get(acrRolePrimaryContact).Id
                        && acrRoleAndContactMap.get(roleType).Contact.Email != contactMap.get('OwnerSignatory').Email){
                            
                            acrRoleAndContactMap.get(roleType).Roles = null;
                            existingAccountContactList.add(acrRoleAndContactMap.get(roleType));
                        }
                    }
                     
                    else if(roleType == acrRoleLegal && contactMap.containskey('LegalPrimaryContact')){
                        
                        if(!isDirectlyLinked && contactTypeContactMap.get('LegalPrimaryContact').Email == acrRoleAndContactMap.get(roleType).Contact.Email){
                            
                            contactMap.get('LegalPrimaryContact').AccountId = acrRoleAndContactMap.get(roleType).Contact.AccountId;
                        }
                        if(acrRoleAndContactMap.get(roleType).Id != acrRoleAndContactMap.get(acrRolePrimaryContact).Id){
                            
                            contactMap.get('LegalPrimaryContact').Id = acrRoleAndContactMap.get(roleType).ContactId;
                        } 
                        else if(acrRoleAndContactMap.get(roleType).Id == acrRoleAndContactMap.get(acrRolePrimaryContact).Id
                        && acrRoleAndContactMap.get(roleType).Contact.Email != contactMap.get('LegalPrimaryContact').Email
                        && contactMap.containsKey('OwnerSignatory') && contactMap.get('OwnerSignatory').Email != contactMap.get('LegalPrimaryContact').Email){
                            List<String> rolesArray = acrRoleAndContactMap.get(roleType).Roles.split(';');
                            
                            rolesArray.remove(rolesArray.indexOf(acrRoleLegal));
                            acrRoleAndContactMap.get(roleType).Roles = String.join(rolesArray,';');
                            existingAccountContactList.add(acrRoleAndContactMap.get(roleType));
                        }
                    }
                }
            }
            //SVS2493
            if (!contactMap.isEmpty()) {
                startTimestamp = DateTime.now();
                try{
                    
                    String moduleValueText ='';
                    //SVS-2676
                    if(!ownerSignatoryIsPrimary){
                        if(!contactTypeCheckboxValueMap.isEmpty()){
                            for(String contactType : contactTypeCheckboxValueMap.keyset()){
                                
                                if(contactTypeCheckboxValueMap.get(contactType) == true){
                                    contactMap.remove(contactType);
                                }
                            }
                        }
                    } 
                    
                    //SVS-2338
                    unitOfWorkObj.registerNewOrChanged(contactMap.values());
                    //unitOfWorkObj.registerNew(contactMap.values());
                    //SVS-2338
                    unitOfWorkObj.save();
                    unitOfWorkObj.clear();
                    List<Id> ContactIdList = new List<Id>();
                    ContactIdList.addAll((new Map<Id, Contact>(contactMap.values())).keyset());
                    
                    moduleValueText += 'Contact Saved: ' + String.join(ContactIdList, ',');
                        
                    SPMOnboardController.getInstance().logInstrumentation(
                        parentInstrumentationId,
                        'Contacts', 
                        SVSConstants.INSTRUMENTATION_STATUS_SUCCESS, 
                        moduleValueText,
                        startTimestamp); 
                } catch(exception ex){
                    SPMOnboardController.getInstance().logInstrumentation(
                        parentInstrumentationId,
                        'Contacts', 
                        SVSConstants.INSTRUMENTATION_STATUS_FAILURE, 
                        ex.getMessage().left(255), 
                        startTimestamp);
                }
                
            }
            List<AccountContactRelation> accountContactRelationList = SPMQuerySelector.getInstance().getAccountContactRelationRecords(contactTypeContactMap, partnerAccId);
            
            if(accountContactRelationList != null && !accountContactRelationList.isEmpty()){
                for(AccountContactRelation accountContactRelationRecord : accountContactRelationList){
                    contactToACRMap.put(accountContactRelationRecord.ContactId, accountContactRelationRecord);
                }
            }
            for(String contactType : contactTypeContactMap.keySet()) {
                if (contactTypeContactMap.containsKey(contactType)
                    && contactToACRMap.containsKey(contactTypeContactMap.get(contactType).id)
                    && contactTypeContactMap.get(contactType).id == contactToACRMap.get(contactTypeContactMap.get(contactType).id).contactId) {
                    contactToACRMap.get(contactTypeContactMap.get(contactType).Id).Id = contactToACRMap.get(contactTypeContactMap.get(contactType).Id).Id;
                    String roles = '';
                    
                    if(string.isNotBlank(contactToACRMap.get(contactTypeContactMap.get(contactType).Id).Roles)){
                        roles = contactToACRMap.get(contactTypeContactMap.get(contactType).Id).Roles;
                    }
                    roles += contactType == 'OwnerSignatory' ?
                            (String.isNotBlank(roles) ? 
                                (roles.contains('Primary Contact') ?
                                '' 
                                : ';Primary Contact') 
                                : 'Primary Contact')  
                        : (String.isNotBlank(roles) ? 
                                (roles.contains('Legal') ? 
                                ''
                                : ';Legal') 
                                : 'Legal');
                                
                        contactToACRMap.get(contactTypeContactMap.get(contactType).Id).Roles = roles;
                }
                else {
                    AccountContactRelation accountContactRelation = new AccountContactRelation();
                    accountContactRelation.AccountId = partnerAccId;
                    accountContactRelation.ContactId = contactTypeContactMap.get(contactType).id;
                    accountContactRelation.Roles = contactType == 'OwnerSignatory' ? 'Primary Contact'  
                        : 'Legal';
                        
                    contactToACRMap.put(contactTypeContactMap.get(contactType).id, accountContactRelation);
                }   
            }
            //SVS2493
            if(existingAccountContactList.size()>0){
                for(AccountContactRelation accountcontacts: existingAccountContactList){
                    contactToACRMap.put(accountcontacts.ContactId, accountcontacts);
                }
            }
            //SVS2493 
            if(!contactToACRMap.isEmpty()){
                startTimestamp = DateTime.now();

                try{
                    
                    String moduleValueText ='';
                    unitOfWorkObj.registerNewOrChanged(contactToACRMap.values());
                    unitOfWorkObj.save();
                    unitOfWorkObj.clear();
                   
                    
                    moduleValueText += 'AccountContactRelation Saved: ' + String.valueOf(contactToACRMap.values()[0].Id);
                    
                    SPMOnboardController.getInstance().logInstrumentation(
                        parentInstrumentationId,
                        'Contacts', 
                        SVSConstants.INSTRUMENTATION_STATUS_SUCCESS, 
                        moduleValueText, 
                        startTimestamp); 
                        defaultContactRole(partnerAccId, parentInstrumentationId);
                    //upsert contactToACRMap.values();
                } catch(exception ex){
                    
                    SPMOnboardController.getInstance().logInstrumentation(
                        parentInstrumentationId,
                        'Contacts', 
                        SVSConstants.INSTRUMENTATION_STATUS_FAILURE, 
                        ex.getMessage().left(255), 
                        startTimestamp);
                }

            }
            return contactMap.values();
        }
        return null;
    }
    */

    /**
    * Method Name : fetchAllContactsData
    * Description : Used to preload the contact details on the Contacts page of the onboard flow
    * Created By  : Aditya Moro
    */
    @AuraEnabled
    public static AllContactsDataWrapper fetchAllContactsData(String partnerAccountId, String ownerSignatoryContact){
        List<AccountContactRelation> accountContactRelationList = new List<AccountContactRelation>();
        AllContactsDataWrapper allContactsData = new AllContactsDataWrapper();
        allContactsData.isBillingPrimaryChecked = false;
        allContactsData.isLegalPrimaryChecked = false;
        allContactsData.isOwnerSignatoryChecked = false;
        
        accountContactRelationList = SPMQuerySelector.getInstance().getAllContactsData(partnerAccountId);
        
        for(AccountContactRelation accountContactRecord: accountContactRelationList){
            Boolean isPrimary = false;
            
            if(accountContactRecord != null && accountContactRecord.Roles != null){
                if(accountContactRecord.Roles.contains('Primary Contact')){
                    allContactsData.primaryContact = accountContactRecord;
                    isPrimary = true;
                    if(accountContactRecord.ContactId == ownerSignatoryContact){
                        
                        allContactsData.isOwnerSignatoryChecked = true;
                    }
                }
                 
                if(accountContactRecord.Roles.contains('Legal')){
                    allContactsData.legalContact = accountContactRecord;
                    
                    if(isPrimary){
                        allContactsData.isLegalPrimaryChecked = true;
                    }
                }
            }
        }

        return allContactsData;
    }

    /**
    * Method Name : defaultContactRole
    * Description : Used to add auto default role on contact.
    * Created By  : Amol Sable
    */
    public static void defaultContactRole(String partnerAccountId, Id parentInstrumentationId){
        Id partnerAccountRecordType;
        String accountTypeOutsourcedAgencyPartner;
        String accountTypeAPIOnlyPartner;
        String accountTypePartner; 
        String aCRRoleLegal;
        String aCRRolePrimaryContact;
        String roleMaster;
        String roleRetailer; 
        String roleWholesaler; 
        String roleReseller; 
        String roleFulfillment; 
        String roleCareSupport;
        String contactRoleNone; 
        String contactRoleReadOnly; 
        String contactRoleUserAdministrator; 
        String contactRolePartnerOnboardAdministrator; 
        String ContactRolesalesAgent; 
        String ContactRolesalesAgentSupervisor;
        String contactRoleCareAgent; 
        IUnitOfWork unitOfWorkObj = UnitOfWork.newInstance(SPMBUContactsController.class);
        DateTime startTimestamp = DateTime.now();
        List<AccountContactRelation> accContactRelationList = new List<AccountContactRelation>();
        List<AccountContactRelation> accountContactRelationList = new List<AccountContactRelation>();
      
        if(String.isNotBlank(partnerAccountId)){
            
            Set<String> developerNameSet = new Set<String>{
                'AccountPartnerRecordType',
                'AccountTypeOutsourcedAgencyPartner',
                'AccountTypeAPIOnlyPartner',
                'AccountType', 
                'ACRRoleLegal',
                'ACRRolePrimaryContact',
                'ContactRoleNone',
                'ContactRoleReadOnly',
                'ContactRoleUserAdministrator',
                'ContactRolePartnerOnboardAdministrator',
                'ContactRolesalesAgent',
                'ContactRolesalesAgentSupervisor',
                'ContactRoleCareAgent',
                'AccountRoleMasterAgent',
                'AccountRoleCareOrSupportPartner',
                'AccountRoleFulfillmentPartner',
                'AccountRoleRetailSalesPartner',
                'AccountRoleWholesaleSalesPartner',
                'AccountRoleResellerSalesPartner'
            };
                        
            Schema.DescribeSObjectResult accDescribe = Schema.SObjectType.Account; 
            Map<String,Schema.RecordTypeInfo> accRecordTypeByDevNameMap = accDescribe.getRecordTypeInfosByDeveloperName();
            
            GPPOnboardingSettings__mdt[] gppOnboardingSettingsList = SPMQuerySelector.getInstance().getGPPOnboardingSettingData(developerNameSet);
            
            for(GPPOnboardingSettings__mdt gppOnboardingSetting : gppOnboardingSettingsList){
                if(gppOnboardingSetting.DeveloperName == 'AccountPartnerRecordType' && accRecordTypeByDevNameMap.containsKey(gppOnboardingSetting.Value__c)){
                    partnerAccountRecordType = accRecordTypeByDevNameMap.get(gppOnboardingSetting.Value__c).getRecordTypeId();        
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountTypeOutsourcedAgencyPartner'){
                    accountTypeOutsourcedAgencyPartner = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountTypeAPIOnlyPartner'){
                    accountTypeAPIOnlyPartner = gppOnboardingSetting.Value__c;
                }
                
                if(gppOnboardingSetting.DeveloperName == 'ACRRoleLegal'){
                    aCRRoleLegal = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'ACRRolePrimaryContact'){
                    aCRRolePrimaryContact = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountType'){
                    accountTypePartner = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'ContactRoleNone'){
                    contactRoleNone = gppOnboardingSetting.Value__c;        
                }
                if(gppOnboardingSetting.DeveloperName == 'ContactRoleReadOnly'){
                    contactRoleReadOnly = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'ContactRoleUserAdministrator'){
                    contactRoleUserAdministrator = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'ContactRolePartnerOnboardAdministrator'){
                    contactRolePartnerOnboardAdministrator = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'ContactRolesalesAgent'){
                    ContactRolesalesAgent = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'ContactRolesalesAgentSupervisor'){
                    ContactRolesalesAgentSupervisor = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'ContactRoleCareAgent'){
                    contactRoleCareAgent = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountRoleMasterAgent'){
                    roleMaster = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountRoleCareOrSupportPartner'){
                    roleCareSupport = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountRoleFulfillmentPartner'){
                    roleFulfillment = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountRoleRetailSalesPartner'){
                    roleRetailer  = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountRoleWholesaleSalesPartner'){
                    roleWholesaler = gppOnboardingSetting.Value__c;
                }
                if(gppOnboardingSetting.DeveloperName == 'AccountRoleResellerSalesPartner'){
                    roleReseller = gppOnboardingSetting.Value__c;
                }
            }
            
            accContactRelationList = SPMQuerySelector.getInstance().getAllContactsData(partnerAccountId);
            Set<Id> contactIdSet = new Set<Id>();

            if(!accContactRelationList.isEmpty()){
                
                for(AccountContactRelation accountContactRelation : accContactRelationList){
                    if (String.isNotBlank(accountContactRelation.Roles)) {
                        contactIdSet.add(accountContactRelation.ContactId); // $
                    }
                }
                accountContactRelationList = SPMQuerySelector.getInstance().getACRDefaultContactRole(contactIdSet, partnerAccountRecordType); 
            }
            

            map<Id,Contact> contactUpdateMap = new map<Id,Contact>();
            if(!accountContactRelationList.isEmpty()){
                for(AccountContactRelation accountContactRelation : accountContactRelationList){
                    Contact contact = ContactUpdateMap.containsKey(accountContactRelation.ContactId) ? 
                        contactUpdateMap.get(accountContactRelation.ContactId) : new Contact(Id = accountContactRelation.ContactId);

                    Set<String> acrRolesSet = accountContactRelation.Roles != null? new Set<String>(accountContactRelation.Roles.split(';')) : new Set<String>();
                    Set<String> contactRolesSet = contact.Roles__c != null? new Set<String>(contact.Roles__c.split(';')) : new set<String>();
                    Set<String> accountRolesSet = accountContactRelation.Account.Roles__c != null? new Set<String>(accountContactRelation.Account.Roles__c.split(';')) : new set<String>();
                    //If Partner is API Only
                    if(accountTypeAPIOnlyPartner.equals(accountContactRelation.Account.Type) && contactRolesSet.isEmpty()){
                        contactRolesSet.add(contactRoleNone);
                        } else{
                        //If Partner is a Distributor/Master Agent    
                        if(accountRolesSet.contains(roleMaster)){
                            if (acrRolesSet.contains(aCRRolePrimaryContact)) {
                                contactRolesSet.remove(contactRoleReadOnly);
                                contactRolesSet.remove(contactRoleNone);
                                contactRolesSet.add(contactRoleUserAdministrator);
                                contactRolesSet.add(contactRolePartnerOnboardAdministrator);
                            } else if ( acrRolesSet.contains(aCRRoleLegal) && contactRolesSet.isEmpty()) {
                                contactRolesSet.add(contactRoleReadOnly);
                            }
                        }  
                        //If a Partner is a Retail, Wholesaler or Resaler AND it is not an Outsource Agency Partner
                        if(accountTypePartner.equals(accountContactRelation.Account.Type)
                            && (accountRolesSet.contains(roleRetailer) 
                            || accountRolesSet.contains(roleWholesaler) 
                            || accountRolesSet.contains(roleReseller))) {
                                if (acrRolesSet.contains(aCRRolePrimaryContact)) {
                                    contactRolesSet.remove(contactRoleReadOnly);
                                    contactRolesSet.remove(contactRoleNone);
                                    contactRolesSet.add(contactRoleUserAdministrator);
                                    contactRolesSet.add(ContactRolesalesAgent);
                                    contactRolesSet.add(ContactRolesalesAgentSupervisor);
                                } else if ( acrRolesSet.contains(aCRRoleLegal) && contactRolesSet.isEmpty()) {
                                    contactRolesSet.add(contactRoleReadOnly);
                                }
                        }  
                        //If a Partner is a Retail AND it is an Outsource Agency Partner
                        if(accountTypeOutsourcedAgencyPartner.equals(accountContactRelation.Account.Type)
                            && accountRolesSet.contains(roleRetailer)) {
                                if (acrRolesSet.contains(aCRRolePrimaryContact)) {
                                    contactRolesSet.remove(contactRoleReadOnly);
                                    contactRolesSet.remove(contactRoleNone);
                                    contactRolesSet.add(ContactRolesalesAgent);
                                    contactRolesSet.add(ContactRolesalesAgentSupervisor);
                                } else if (acrRolesSet.contains(aCRRoleLegal) && contactRolesSet.isEmpty()) {
                                    contactRolesSet.add(contactRoleNone);
                                }
                        }  
                        //If a Partner is ONLY a Fulfillment Partner
                        if (accountRolesSet.contains(roleFulfillment) && contactRolesSet.isEmpty()) {
                            contactRolesSet.add(contactRoleNone);
                        } 
                        //If a Partner is ONLY Care/Support Partner AND it is an Outsource Agency Partner 
                        if(accountTypeOutsourcedAgencyPartner.equals(accountContactRelation.Account.Type) 
                            && accountRolesSet.contains(roleCareSupport)) {
                                if (acrRolesSet.contains(aCRRolePrimaryContact)) {
                                    contactRolesSet.remove(contactRoleReadOnly);
                                    contactRolesSet.remove(contactRoleNone);
                                    contactRolesSet.add(contactRoleCareAgent);
                                } else if (acrRolesSet.contains(aCRRoleLegal) && contactRolesSet.isEmpty()) {
                                    contactRolesSet.add(contactRoleNone);
                                }    
                        }
                        //If a Partner is Care/Support and Fulfillment Partner AND it is an Outsource Agency Partner 
                        if(accountTypeOutsourcedAgencyPartner.equals(accountContactRelation.Account.Type) 
                            && accountRolesSet.contains(roleCareSupport) 
                            && accountRolesSet.contains(roleFulfillment)) {
                                if (acrRolesSet.contains(aCRRolePrimaryContact)) {
                                    contactRolesSet.remove(contactRoleReadOnly);
                                    contactRolesSet.remove(contactRoleNone);
                                    contactRolesSet.add(contactRoleCareAgent);
                                } else if (acrRolesSet.contains(aCRRoleLegal) && contactRolesSet.isEmpty()) {
                                    contactRolesSet.add(contactRoleNone);
                                }    
                        }
                    }

                    contact.Roles__c = String.join(new List<String>(contactRolesSet),';');
                    contactUpdateMap.put(contact.Id,contact);
                }
                if(!contactUpdateMap.isEmpty()){
                    startTimestamp = DateTime.now();
                    try{
                        String moduleValueText ='';
                        unitOfWorkObj.registerChanged(ContactUpdateMap.values());
                        unitOfWorkObj.save();
                        unitOfWorkObj.clear();
                        List<Id> contactIdList = new List<Id>();
                        contactIdList.addAll((new Map<Id, Contact>(contactUpdateMap.values())).keyset());
                        moduleValueText += 'Contact Saved: ' + String.join(contactIdList, ',');
                        //moduleValueText += 'Contact Saved: ' + String.join(new List<String>(ContactUpdateMap.keySet()), ',');
                            
                        SPMOnboardController.getInstance().logInstrumentation(
                            parentInstrumentationId,
                            'Contacts', 
                            SVSConstants.INSTRUMENTATION_STATUS_SUCCESS, 
                            moduleValueText,
                            startTimestamp);  
                    } catch(exception ex){
                        
                        SPMOnboardController.getInstance().logInstrumentation(
                            parentInstrumentationId,
                            'Contacts', 
                            SVSConstants.INSTRUMENTATION_STATUS_FAILURE, 
                            ex.getMessage().left(255), 
                            startTimestamp);
                    }
                }
            }  
        }
    }

    public class AllContactsDataWrapper{
        @AuraEnabled
        public AccountContactRelation primaryContact;
        @AuraEnabled
        public AccountContactRelation billingPrimaryContact;
        @AuraEnabled
        public AccountContactRelation legalContact;
        @AuraEnabled
        public Boolean isOwnerSignatoryChecked;
        @AuraEnabled
        public Boolean isBillingPrimaryChecked;
        @AuraEnabled
        public Boolean isLegalPrimaryChecked;
    }

    public class primaryAndLegalContactResultWrapper{
        @AuraEnabled
        public Contact primaryContact;
        
        @AuraEnabled
        public List<String> newOrUpdatedContactIdList;
        
        public primaryAndLegalContactResultWrapper(){
            primaryContact = new Contact();
            newOrUpdatedContactIdList = new List<String>();
        }
        
    }
}