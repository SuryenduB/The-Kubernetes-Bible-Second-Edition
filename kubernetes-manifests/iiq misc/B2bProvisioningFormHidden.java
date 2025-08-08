
                                   import sailpoint.object.Form;
                      
                                   Object objType = field.getValue();
                                   
                                   String requiredAttribute = "|userPrincipalName|displayName|mailNickname|password|";
                                   String booleanAttr = "|sendInvitationMessage|forceChangePasswordNextLogin|accountEnabled|enableLocalAccount|b2cForceChangePasswordNextLogin|enableSocialAccount|";
                                   String locationAttr = "|invitedUserUsageLocation|usageLocation|";
                                   
                                   Form.Section section = null ;
                                   
                                   for(Form.Section s : form.getSections()) {
                               
                                      if (s != null && !(objType.equals(s.getName()) ) && !("Account".equals(s.getName())) ) {
                                        form.remove(s);
                                     
                                      }
                                   }
                                   
                                   
                                   switch(objType) {
                                   
                                      case "Guest User B2B"   : section = form.getSection("Guest User B2B");
                                                                requiredAttribute = "|invitedUserEmailAddress|inviteRedirectUrl|sendInvitationMessage|";
                                                                break;
                                      case "User"             : section = form.getSection("User");
                                                                requiredAttribute = "|userPrincipalName|displayName|mailNickname|password|";
                                                                break;
                                      case "Local User B2C"   : section = form.getSection("Local User B2C");
                                                                requiredAttribute = "|signInNameType|signInNameValue|localAccountDisplayName|b2cPassword|";
                                   }
                                   
                                   
                                   if (section != null && section.getFields() != null ) {
                                        
                                        for (Object field : section.getFields()) {
                                             String name = field.getName();
                                             if (name != null && name.indexOf(":") > 0 ) {
                                                 String[] nameKeys = name.split(":");
                                                 
                                                 if( !(nameKeys.length > 2) ) {
                                                    continue;
                                                 }
                                                 
                                                 if ( requiredAttribute.contains("|" + nameKeys[2] + "|") ) {
                                                     field.setRequired(true);
                                                 }
                                                 
                                                 if ( booleanAttr.contains("|" + nameKeys[2] + "|") ) {
                                                     field.setValue("true");
                                                 }
                                                 
                                                 if ( locationAttr.contains("|" + nameKeys[2] + "|") ) {
                                                     field.setValue("United States;US");
                                                 }
                                             }              
                                          }
                                   
                                   }
                                   
                                   return false;
                               