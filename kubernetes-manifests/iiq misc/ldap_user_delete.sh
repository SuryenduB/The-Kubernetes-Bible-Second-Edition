#!/bin/bash

# LDAP User Deletion Script
# Lists all users in an LDAP OU and deletes them

# Configuration - Modify these variables as needed
LDAP_SERVER="ldap://localhost:389"
BASE_DN="dc=sailpoint,dc=demo"
USERS_OU="ou=people,dc=sailpoint,dc=demo"
BIND_DN="cn=admin,dc=sailpoint,dc=demo"
SEARCH_FILTER="(objectClass=inetOrgPerson)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if required commands exist
check_dependencies() {
    local deps=("ldapsearch" "ldapdelete")
    local missing_deps=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing required commands: ${missing_deps[*]}"
        print_error "Please install OpenLDAP client tools"
        exit 1
    fi
}

# Function to get bind DN and password from user
get_bind_dn_and_pass() {
    while [ -z "$BIND_DN" ]; do
        read -p "Enter Bind DN (e.g., cn=admin,dc=sailpoint,dc=demo): " BIND_DN
        if [ -z "$BIND_DN" ]; then
            print_warning "Bind DN cannot be empty"
        fi
    done
    if [ -z "$LDAP_PASS" ]; then
        read -s -p "Enter LDAP Password: " LDAP_PASS
        echo
    fi
}

# Function to test LDAP connection
test_ldap_connection() {
    print_info "Testing LDAP connection..."
    if ldapsearch -x -H "$LDAP_SERVER" -D "$BIND_DN" -w "$LDAP_PASS" -b "$BASE_DN" -s base "objectClass=*" > /dev/null 2>&1; then
        print_success "LDAP connection successful"
        return 0
    else
        print_error "LDAP connection failed"
        return 1
    fi
}

# Function to list all users in the OU
list_users() {
    print_info "Searching for users in $USERS_OU..."
    # Search for users and extract DNs
    local user_dns=$(ldapsearch -x -H "$LDAP_SERVER" -D "$BIND_DN" -w "$LDAP_PASS" -b "$USERS_OU" "$SEARCH_FILTER" dn 2>/dev/null | grep "^dn: " | cut -d' ' -f2-)
    if [ -z "$user_dns" ]; then
        print_warning "No users found in $USERS_OU"
        return 1
    fi
    # Convert to array
    IFS=$'\n' read -rd '' -a user_array <<< "$user_dns"
    print_info "Found ${#user_array[@]} user(s):"
    echo "----------------------------------------"
    for i in "${!user_array[@]}"; do
        echo "$((i+1)). ${user_array[i]}"
    done
    echo "----------------------------------------"
    return 0
}

# Function to confirm deletion
confirm_deletion() {
    local count=${#user_array[@]}
    print_warning "You are about to delete $count user(s)!"
    read -p "Are you sure you want to proceed? (yes/no): " confirmation
    
    case "$confirmation" in
        yes|YES|y|Y)
            return 0
            ;;
        *)
            print_info "Deletion cancelled"
            return 1
            ;;
    esac
}

# Function to delete users
delete_users() {
    local success_count=0
    local failed_count=0
    local failed_users=()
    print_info "Starting user deletion process..."
    for i in "${!user_array[@]}"; do
        local user_dn="${user_array[i]}"
        local user_number=$((i+1))
        local total_count=${#user_array[@]}
        echo -n "Deleting user $user_number/$total_count: $user_dn ... "
        if ldapdelete -x -H "$LDAP_SERVER" -D "$BIND_DN" -w "$LDAP_PASS" "$user_dn" > /dev/null 2>&1; then
            echo -e "${GREEN}SUCCESS${NC}"
            ((success_count++))
        else
            echo -e "${RED}FAILED${NC}"
            failed_count=$((failed_count + 1))
            failed_users+=("$user_dn")
        fi
    done
    echo "----------------------------------------"
    print_success "Deletion Summary:"
    print_success "Successfully deleted: $success_count user(s)"
    if [ $failed_count -gt 0 ]; then
        print_error "Failed to delete: $failed_count user(s)"
        print_error "Failed users:"
        for failed_user in "${failed_users[@]}"; do
            print_error "  - $failed_user"
        done
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -s, --server URI    LDAP server URI (default: ldap://localhost:389)"
    echo "  -b, --base-dn DN    Base DN (default: dc=sailpoint,dc=demo)"
    echo "  -o, --ou DN         Users OU DN (default: ou=people,dc=sailpoint,dc=demo)"
    echo "  -f, --filter FILTER Search filter (default: (objectClass=person))"
    echo ""
    echo "Examples:"
    echo "  $0"
    echo "  $0 -s ldap://ldap.example.com:389 -o ou=employees,dc=sailpoint,dc=demo"
    echo "  $0 --server ldaps://secure.example.com:636 --ou ou=staff,dc=company,dc=com"
}

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -s|--server)
                LDAP_SERVER="$2"
                shift 2
                ;;
            -b|--base-dn)
                BASE_DN="$2"
                USERS_OU="$2"
                shift 2
                ;;
            -o|--ou)
                USERS_OU="$2"
                shift 2
                ;;
            -f|--filter)
                SEARCH_FILTER="$2"
                shift 2
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
}

# Main function
main() {
    # Parse command line arguments
    parse_arguments "$@"
    print_info "LDAP User Deletion Script"
    echo "========================================"
    # Check dependencies
    check_dependencies
    # Get bind DN and password
    get_bind_dn_and_pass
    # Test LDAP connection
    if ! test_ldap_connection; then
        exit 1
    fi
    echo ""
    # List users
    if ! list_users; then
        exit 0
    fi
    echo ""
    # Confirm deletion
    if ! confirm_deletion; then
        exit 0
    fi
    echo ""
    # Delete users
    delete_users
    print_info "Script completed"
}

# Run main function
main "$@"