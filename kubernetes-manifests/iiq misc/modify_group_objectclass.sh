#!/bin/bash

# Configuration
BASE_DN="ou=groups,dc=sailpoint,dc=demo"
ADMIN_DN="cn=admin,dc=sailpoint,dc=demo"

# Auto-detect LDAP server in Kubernetes environment
if [ -n "$KUBERNETES_SERVICE_HOST" ]; then
    # Try common LDAP service names in Kubernetes
    LDAP_HOST="${LDAP_HOST:-ldap-service}"
    if [ -z "$(getent hosts ldap-service 2>/dev/null)" ]; then
        LDAP_HOST="${LDAP_HOST:-openldap}"
    fi
    if [ -z "$(getent hosts openldap 2>/dev/null)" ]; then
        LDAP_HOST="${LDAP_HOST:-ldap}"
    fi
else
    LDAP_HOST="${LDAP_HOST:-localhost}"
fi

LDAP_PORT="${LDAP_PORT:-389}"
LOG_FILE="ldap_group_modification_$(date +%Y%m%d_%H%M%S).log"
ERROR_LOG="ldap_errors_$(date +%Y%m%d_%H%M%S).log"

# Authentication options (choose one method)
# Method 1: Password file (recommended)
LDAP_PASSWORD_FILE="${LDAP_PASSWORD_FILE:-~/.ldap_admin_password}"

# Method 2: Environment variable
# Export LDAP_ADMIN_PASSWORD in your environment

# Method 3: SASL/Kerberos (if configured)
USE_SASL="${USE_SASL:-false}"

# Initialize counters
TOTAL_GROUPS=0
SUCCESSFUL_MODIFICATIONS=0
FAILED_MODIFICATIONS=0
GROUPS_WITH_MEMBERS=0
GROUPS_WITHOUT_MEMBERS=0

# Logging functions
log_info() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO: $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $message" | tee -a "$LOG_FILE" | tee -a "$ERROR_LOG"
}

log_warn() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN: $message" | tee -a "$LOG_FILE"
}

log_success() {
    local message="$1"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS: $message" | tee -a "$LOG_FILE"
}

# Authentication setup function
setup_auth() {
    if [ "$USE_SASL" = "true" ]; then
        log_info "Using SASL/Kerberos authentication"
        LDAP_AUTH_ARGS=""
        return 0
    fi
    
    # Try password file first
    if [ -f "$LDAP_PASSWORD_FILE" ]; then
        log_info "Using password file: $LDAP_PASSWORD_FILE"
        LDAP_AUTH_ARGS="-D $ADMIN_DN -y $LDAP_PASSWORD_FILE"
        return 0
    fi
    
    # Try environment variable
    if [ -n "$LDAP_ADMIN_PASSWORD" ]; then
        log_info "Using password from environment variable"
        LDAP_AUTH_ARGS="-D $ADMIN_DN -w $LDAP_ADMIN_PASSWORD"
        return 0
    fi
    
    log_error "No authentication method configured. Please set one of:"
    log_error "  1. Create password file: echo 'your_password' > ~/.ldap_admin_password && chmod 600 ~/.ldap_admin_password"
    log_error "  2. Set environment variable: export LDAP_ADMIN_PASSWORD='your_password'"
    log_error "  3. Use SASL: export USE_SASL=true"
    return 1
}

# Enhanced connectivity test
test_ldap_connection() {
    log_info "Testing LDAP connectivity to $LDAP_HOST:$LDAP_PORT"
    
    # In Kubernetes, try to discover the correct LDAP service
    if [ -n "$KUBERNETES_SERVICE_HOST" ]; then
        log_info "Kubernetes environment detected, checking for LDAP services..."
        
        # Try common service names
        for service in ldap-service openldap ldap slapd; do
            if getent hosts "$service" >/dev/null 2>&1; then
                log_info "Found LDAP service: $service"
                LDAP_HOST="$service"
                break
            fi
        done
        
        # List available services for debugging
        log_info "Available services in cluster:"
        if command -v nslookup >/dev/null 2>&1; then
            nslookup -type=srv _ldap._tcp 2>/dev/null | grep -E "service|SRV" | head -5 | while read line; do
                log_info "  $line"
            done
        fi
    fi
    
    # Test basic connectivity
    log_info "Testing network connectivity to $LDAP_HOST:$LDAP_PORT"
    if command -v nc >/dev/null 2>&1; then
        if ! nc -z "$LDAP_HOST" "$LDAP_PORT" 2>/dev/null; then
            log_error "Cannot connect to LDAP server at $LDAP_HOST:$LDAP_PORT"
        else
            log_success "Network connectivity to $LDAP_HOST:$LDAP_PORT successful"
        fi
    elif command -v telnet >/dev/null 2>&1; then
        if ! timeout 5 telnet "$LDAP_HOST" "$LDAP_PORT" </dev/null >/dev/null 2>&1; then
            log_error "Cannot connect to LDAP server at $LDAP_HOST:$LDAP_PORT"
        else
            log_success "Network connectivity to $LDAP_HOST:$LDAP_PORT successful"
        fi
    else
        log_warn "Neither nc nor telnet available, skipping network connectivity test"
    fi
    
    # Show debugging information
    log_info "LDAP connection debugging information:"
    log_info "  Hostname resolution for $LDAP_HOST:"
    if getent hosts "$LDAP_HOST" 2>/dev/null; then
        getent hosts "$LDAP_HOST" | while read line; do
            log_info "    $line"
        done
    else
        log_error "    Cannot resolve hostname: $LDAP_HOST"
        
        # Suggest alternatives
        log_info "  Trying to find LDAP services in the environment..."
        if [ -n "$KUBERNETES_SERVICE_HOST" ]; then
            log_info "  You might need to set LDAP_HOST to one of:"
            for service in ldap-service openldap ldap slapd; do
                if getent hosts "$service" >/dev/null 2>&1; then
                    log_info "    export LDAP_HOST=$service"
                fi
            done
        fi
        
        log_error "Please check:"
        log_error "  - LDAP server service name (try: kubectl get services)"
        log_error "  - Set correct LDAP_HOST environment variable"
        log_error "  - LDAP server is running"
        log_error "  - Network connectivity"
        log_error "  - Firewall settings"
        return 1
    fi
    
    # Test LDAP search with authentication
    if [ "$USE_SASL" = "true" ]; then
        TEST_CMD="ldapsearch -H ldap://$LDAP_HOST:$LDAP_PORT -LLL -b '$BASE_DN' '(objectClass=*)' dn"
    else
        TEST_CMD="ldapsearch -H ldap://$LDAP_HOST:$LDAP_PORT -x -LLL $LDAP_AUTH_ARGS -b '$BASE_DN' '(objectClass=*)' dn"
    fi
    
    log_info "Testing LDAP search with authentication..."
    log_info "Command: $TEST_CMD"
    
    if ! eval "$TEST_CMD" >/dev/null 2>&1; then
        log_error "LDAP authentication or search failed"
        log_error "Please check:"
        log_error "  - Admin DN: $ADMIN_DN"
        log_error "  - Base DN: $BASE_DN"
        log_error "  - Credentials are correct"
        log_error "  - User has sufficient privileges"
        log_error "  - LDAP server is properly configured"
        
        # Try a simple anonymous bind test
        log_info "Trying anonymous LDAP search to test server availability..."
        if ldapsearch -H "ldap://$LDAP_HOST:$LDAP_PORT" -x -LLL -b '' -s base '(objectclass=*)' 2>/dev/null; then
            log_info "Anonymous LDAP search successful - server is reachable"
            log_error "Issue is likely with authentication credentials"
        else
            log_error "Even anonymous LDAP search failed - server may not be properly configured"
        fi
        
        return 1
    fi
    
    return 0
}

# Cleanup function
cleanup() {
    if [ -f "modify.ldif" ]; then
        rm -f modify.ldif
        log_info "Cleaned up temporary LDIF file"
    fi
}

# Set up trap for cleanup
trap cleanup EXIT

# Start logging
log_info "=== LDAP Group Modification Script Started ==="
log_info "Base DN: $BASE_DN"
log_info "Admin DN: $ADMIN_DN"
log_info "LDAP Server: $LDAP_HOST:$LDAP_PORT"
log_info "Log file: $LOG_FILE"
log_info "Error log: $ERROR_LOG"

# Setup authentication
if ! setup_auth; then
    exit 1
fi

# Test LDAP connectivity and authentication
if ! test_ldap_connection; then
    exit 1
fi
log_success "LDAP connectivity and authentication test passed"

# Get all group DNs under the base DN
log_info "Retrieving group DNs from base DN: $BASE_DN"

if [ "$USE_SASL" = "true" ]; then
    SEARCH_CMD="ldapsearch -H ldap://$LDAP_HOST:$LDAP_PORT -LLL -b '$BASE_DN' '(objectClass=*)' dn"
else
    SEARCH_CMD="ldapsearch -H ldap://$LDAP_HOST:$LDAP_PORT -x -LLL $LDAP_AUTH_ARGS -b '$BASE_DN' '(objectClass=*)' dn"
fi

GROUP_DNS=$(eval "$SEARCH_CMD" 2>/dev/null | grep "^dn:" | sed 's/^dn: //')

if [ -z "$GROUP_DNS" ]; then
    log_error "No groups found under base DN: $BASE_DN"
    exit 1
fi

# Count total groups
TOTAL_GROUPS=$(echo "$GROUP_DNS" | wc -l)
log_info "Found $TOTAL_GROUPS groups to process"

# Process each group
echo "$GROUP_DNS" | while read dn; do
    if [ -z "$dn" ]; then
        continue
    fi
    
    log_info "Processing group: $dn"
    
    # Check current objectClasses
    if [ "$USE_SASL" = "true" ]; then
        CURRENT_OBJECTCLASSES=$(ldapsearch -H ldap://$LDAP_HOST:$LDAP_PORT -LLL -b "$dn" objectClass 2>/dev/null | grep '^objectClass:' | sed 's/^objectClass: //')
    else
        CURRENT_OBJECTCLASSES=$(ldapsearch -H ldap://$LDAP_HOST:$LDAP_PORT -x -LLL $LDAP_AUTH_ARGS -b "$dn" objectClass 2>/dev/null | grep '^objectClass:' | sed 's/^objectClass: //')
    fi
    
    log_info "Current objectClasses for $dn:"
    echo "$CURRENT_OBJECTCLASSES" | while read class; do
        if [ -n "$class" ]; then
            log_info "  - $class"
        fi
    done
    
    if echo "$CURRENT_OBJECTCLASSES" | grep -qi "groupOfNames"; then
        log_warn "Group $dn already has groupOfNames objectClass, skipping"
        continue
    fi
    
    # Check if this is a posixGroup that needs to be converted
    if echo "$CURRENT_OBJECTCLASSES" | grep -qi "posixGroup"; then
        log_info "Converting posixGroup to groupOfNames for: $dn"
        
        # For posixGroup conversion, we need to replace the structural class
        cat > modify.ldif <<EOF
dn: $dn
changetype: modify
delete: objectClass
objectClass: posixGroup
-
add: objectClass
objectClass: top
-
add: objectClass
objectClass: groupOfNames
EOF
    else
        log_info "Adding groupOfNames objectClass to: $dn"
        
        # For other groups, just add groupOfNames
        cat > modify.ldif <<EOF
dn: $dn
changetype: modify
add: objectClass
objectClass: groupOfNames
EOF
    fi

    # Check if 'member' attribute exists
    log_info "Checking for existing member attribute in: $dn"
    if [ "$USE_SASL" = "true" ]; then
        HAS_MEMBER=$(ldapsearch -H ldap://$LDAP_HOST:$LDAP_PORT -LLL -b "$dn" member 2>/dev/null | grep '^member:' || true)
    else
        HAS_MEMBER=$(ldapsearch -H ldap://$LDAP_HOST:$LDAP_PORT -x -LLL $LDAP_AUTH_ARGS -b "$dn" member 2>/dev/null | grep '^member:' || true)
    fi
    
    if [ -z "$HAS_MEMBER" ]; then
        log_info "No member attribute found, adding dummy member to: $dn"
        cat >> modify.ldif <<EOF
-
add: member
member: cn=abby.imes@primarygrocers.corp,ou=people,dc=sailpoint,dc=demo
EOF
        GROUPS_WITHOUT_MEMBERS=$((GROUPS_WITHOUT_MEMBERS + 1))
    else
        log_info "Member attribute already exists in: $dn"
        GROUPS_WITH_MEMBERS=$((GROUPS_WITH_MEMBERS + 1))
    fi

    # Log the LDIF content for debugging
    log_info "LDIF content for $dn:"
    while IFS= read -r line; do
        log_info "  $line"
    done < modify.ldif

    # Apply the changes
    log_info "Applying modifications to: $dn"
    if [ "$USE_SASL" = "true" ]; then
        MODIFY_CMD="ldapmodify -H ldap://$LDAP_HOST:$LDAP_PORT -f modify.ldif"
    else
        MODIFY_CMD="ldapmodify -H ldap://$LDAP_HOST:$LDAP_PORT -x $LDAP_AUTH_ARGS -f modify.ldif"
    fi
    
    if eval "$MODIFY_CMD" 2>>"$ERROR_LOG"; then
        log_success "Successfully modified: $dn"
        SUCCESSFUL_MODIFICATIONS=$((SUCCESSFUL_MODIFICATIONS + 1))
    else
        log_error "Failed to modify: $dn (check $ERROR_LOG for details)"
        FAILED_MODIFICATIONS=$((FAILED_MODIFICATIONS + 1))
    fi
    
    # Clean up temporary file
    rm -f modify.ldif
    
    log_info "Completed processing: $dn"
    echo "---"
done

# Final summary
log_info "=== LDAP Group Modification Script Completed ==="
log_info "Total groups processed: $TOTAL_GROUPS"
log_info "Successful modifications: $SUCCESSFUL_MODIFICATIONS"
log_info "Failed modifications: $FAILED_MODIFICATIONS"
log_info "Groups with existing members: $GROUPS_WITH_MEMBERS"
log_info "Groups requiring dummy member: $GROUPS_WITHOUT_MEMBERS"

if [ $FAILED_MODIFICATIONS -gt 0 ]; then
    log_error "Script completed with $FAILED_MODIFICATIONS errors. Check $ERROR_LOG for details."
    exit 1
else
    log_success "Script completed successfully with no errors."
fi