import org.apache.commons.logging.Log;
import org.apache.commons.logging.LogFactory;
import org.apache.commons.lang.StringUtils;
import sailpoint.object.AttributeAssignment;
import sailpoint.api.IdentityService;
import sailpoint.api.ObjectUtil;
import sailpoint.api.SailPointContext;
import sailpoint.api.SailPointFactory;
import sailpoint.api.Provisioner;
import sailpoint.api.*;
import java.util.Calendar;
import sailpoint.object.IdentityEntitlement;
import sailpoint.object.ApprovalItem.ProvisioningState;
import sailpoint.object.Application;
import sailpoint.object.ApprovalItem;
import sailpoint.object.AuditEvent;
import sailpoint.object.Attributes;
import sailpoint.object.AuthenticationAnswer;
import sailpoint.object.AuthenticationQuestion;
import sailpoint.object.Bundle;
import sailpoint.object.Certification;
import sailpoint.object.CertificationEntity;
import sailpoint.object.Custom;
import sailpoint.object.EmailOptions;
import sailpoint.object.EmailTemplate;
import sailpoint.object.Filter;
import sailpoint.object.Form;
import sailpoint.object.Identity;
import sailpoint.object.IdentityRequest;
import sailpoint.object.IdentityRequestItem;
import sailpoint.object.Link;
import sailpoint.object.ManagedAttribute;
import sailpoint.object.ProvisioningPlan;
import sailpoint.object.ProvisioningPlan.AccountRequest;
import sailpoint.object.ProvisioningPlan.AttributeRequest;
import sailpoint.object.ProvisioningPlan.Operation;
import sailpoint.object.ProvisioningPlan.AccountRequest.Operation;
import sailpoint.object.ProvisioningProject;
import sailpoint.object.ProvisioningResult;
import sailpoint.object.QueryOptions;
import sailpoint.object.RoleAssignment;
import sailpoint.object.Field;
import sailpoint.object.Filter;
import sailpoint.object.Form;
import sailpoint.object.WorkItem;
import sailpoint.object.Form.Section;
import sailpoint.object.*;
import sailpoint.object.Request;
import sailpoint.object.Filter.LeafFilter;
import sailpoint.object.Filter.CompositeFilter;
import sailpoint.object.Profile;
import sailpoint.workflow.WorkflowContext;


import sailpoint.tools.GeneralException;
import sailpoint.tools.Message;
import sailpoint.tools.Util;
import sailpoint.tools.xml.XMLObjectFactory;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.Arrays;

// It's a good practice to use a specific logger name to avoid conflicts.
Log buildPlanLogger = LogFactory.getLog("rule.JDBCProvisioningRule");

if (buildPlanLogger.isDebugEnabled()) {
	buildPlanLogger.debug("User getting terminated from the system: " + identityName);
}

        Identity identity = context.getObjectByName(Identity.class, identityName);

        ProvisioningPlan plan = new ProvisioningPlan();
        // Set identity to the plan
        plan.setIdentity(identity);

        List acctReqs = new ArrayList();

        List links = identity.getLinks();

        for(Iterator iterator = links.iterator(); iterator.hasNext();){
        	Link link = (Link) iterator.next();
        	if (buildPlanLogger.isDebugEnabled()) {
        buildPlanLogger.debug("User App: " + link.getApplicationName());
        	}
          if(link.getApplicationName().equalsIgnoreCase("OpenLDAP")){
            AccountRequest ldapAcctReq = new AccountRequest();
            ldapAcctReq.setOperation(AccountRequest.Operation.Modify);
            ldapAcctReq.setNativeIdentity(link.getNativeIdentity());
            ldapAcctReq.setApplication("OpenLDAP");
            ldapAcctReq.add(new AttributeRequest("title", ProvisioningPlan.Operation.Set, "Retired"));
            acctReqs.add(ldapAcctReq);
          }

        if(link.getApplicationName().equalsIgnoreCase("Accounting App")){
          AccountRequest jdbcAcctReq = new AccountRequest();
          jdbcAcctReq.setOperation(AccountRequest.Operation.Disable);
          jdbcAcctReq.setNativeIdentity(link.getNativeIdentity());
          jdbcAcctReq.setApplication("Accounting App");
          acctReqs.add(jdbcAcctReq);
          }
        }


        plan.setAccountRequests(acctReqs);

        workflow.put("plan", plan);
        if (buildPlanLogger.isDebugEnabled()) {
            planXML = plan.toXml();
            buildPlanLogger.debug("Provisioning plan created for user: " + identityName);
            buildPlanLogger.debug("Provisioning plan XML: " + planXML);
        }


        return plan;