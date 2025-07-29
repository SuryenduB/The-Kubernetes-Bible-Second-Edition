import sailpoint.object.ProvisioningResult;
import sailpoint.object.ProvisioningPlan;
import sailpoint.object.Identity;
import sailpoint.object.ProvisioningPlan.AccountRequest;
import sailpoint.object.ProvisioningPlan.AttributeRequest;
import sailpoint.tools.GeneralException;
import sailpoint.tools.Util;

import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.Types;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

boolean addIndexedParameter(PreparedStatement stmt, AccountRequest accountRequest, String parameterName, int index) throws Exception {
    AttributeRequest attributeRequest = accountRequest.getAttributeRequest(parameterName);
    if (attributeRequest == null || attributeRequest.getValue() == null || Util.isNullOrEmpty(Util.otoa(attributeRequest.getValue()))) {
        stmt.setNull(index, Types.VARCHAR);
        return false;
    } else {
        String value = Util.otoa(attributeRequest.getValue());
        stmt.setString(index, value);
        return true;
    }
}

try {
    AccountRequest accountRequest = request;
    //List all Arguments in log.error
    log.error("Provisioning account Request : " + accountRequest.toXml());
    log.error("Provisioning account Plan : " + plan.toXml());
    String username = plan.getNativeIdentity();
    if (Util.isNullOrEmpty(username)) {
        // Set NativeIdentity from the Plan
        throw new GeneralException("A native identity is required for provisioning");
    }

    ProvisioningResult result = new ProvisioningResult();
    String CHECK_SQL = "SELECT 1 FROM users WHERE username = ?";
    String EXISTING_ROLES_SQL = "SELECT role_name FROM roles_users WHERE username = ?";
    String CREATE_SQL = "INSERT INTO users (username, first_name, middle_name, last_name, display_name, emplid, manager_username, enabled) VALUES (?, ?, ?, ?, ?, ?, ?, ?)";
    String INSERT_ROLE_SQL = "INSERT INTO roles_users (role_name, username) VALUES (?, ?)";

    boolean needsCreate = true;
    PreparedStatement checkStatement = connection.prepareStatement(CHECK_SQL);
    try {
        checkStatement.setString(1, username);
        ResultSet results = checkStatement.executeQuery();
        try {
            if (results.next()) {
                needsCreate = false;
            }
        } finally {
            results.close();
        }
    } finally {
        checkStatement.close();
    }

    if (needsCreate) {
        PreparedStatement createStatement = connection.prepareStatement(CREATE_SQL);
        try {
            createStatement.setString(1, username);
            addIndexedParameter(createStatement, accountRequest, "first_name", 2);
            addIndexedParameter(createStatement, accountRequest, "middle_name", 3);
            addIndexedParameter(createStatement, accountRequest, "last_name", 4);
            addIndexedParameter(createStatement, accountRequest, "display_name", 5);
            addIndexedParameter(createStatement, accountRequest, "emplid", 6);
            addIndexedParameter(createStatement, accountRequest, "manager_username", 7);
            addIndexedParameter(createStatement, accountRequest, "enabled", 8);
            createStatement.executeUpdate();
        } finally {
            createStatement.close();
        }
    }

    Set<String> existingRoles = new HashSet<>();
    PreparedStatement existingRolesStmt = connection.prepareStatement(EXISTING_ROLES_SQL);
    try {
        existingRolesStmt.setString(1, username);
        ResultSet results = existingRolesStmt.executeQuery();
        try {
            while (results.next()) {
                existingRoles.add(results.getString(1));
            }
        } finally {
            results.close();
        }
    } finally {
        existingRolesStmt.close();
    }

    PreparedStatement insertRole = connection.prepareStatement(INSERT_ROLE_SQL);
    try {
        for (AttributeRequest attributeRequest : Util.safeIterable(accountRequest.getAttributeRequests())) {
            if (attributeRequest.getName().equalsIgnoreCase("role_name")) {
                List<String> values = Util.otol(attributeRequest.getValue());
                for (String value : Util.safeIterable(values)) {
                    if (!existingRoles.contains(value)) {
                        insertRole.setString(1, value);
                        insertRole.setString(2, username);
                        insertRole.executeUpdate();
                        existingRoles.add(value);
                    }
                }
            }
        }
    } finally {
        insertRole.close();
    }

    result.setStatus(ProvisioningResult.STATUS_COMMITTED);
    return result;
} catch (Exception e) {
    log.error("Caught an exception provisioning an account", e);
    throw e;
}