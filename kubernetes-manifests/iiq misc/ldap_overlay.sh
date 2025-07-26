#!/bin/sh

# Exit immediately if a command exits with a non-zero status.
set -e

################################################################################
# CONFIGURATION
# ------------------------------------------------------------------------------
# !!! IMPORTANT !!!
# UPDATE these variables to match your OpenLDAP setup.
################################################################################

# Your base DN. e.g., "dc=example,dc=demo"
BASE_DN="dc=sailpoint,dc=demo"

# The OU where your groups are stored. e.g., "ou=groups"
GROUPS_OU="ou=groups"

# Your registered Private Enterprise Number (PEN) OID.
# If you don't have one, use a temporary one for testing.
# e.g., "1.3.6.1.4.1.your-org.2.5"
ENTERPRISE_OID="1.3.6.1.4.1.99999"

# The DN of your primary database in cn=config.
# This script attempts to find it, but you should verify it's correct.
# Common values are "olcDatabase={1}mdb,cn=config" or "olcDatabase={1}hdb,cn=config".
# To find it manually, run: sudo ldapsearch -Y EXTERNAL -H ldapi:/// -b cn=config '(olcDatabase=*)' dn
DATABASE_DN="olcDatabase={1}mdb,cn=config"

################################################################################
# SCRIPT LOGIC
# Do not edit below this line unless you know what you are doing.
################################################################################

echo "🚀 Starting OpenLDAP dynlist configuration for posixGroup..."
echo "---------------------------------------------------------"

# --- Step 1: Create and load a custom schema ---
echo "1. Creating custom schema for 'customMemberOf' attribute..."
if ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=schema,cn=config" "(olcAttributeTypes=*${ENTERPRISE_OID}.1.1*)" | grep -q "olcAttributeTypes"; then
  echo "   (Custom attributeType already exists, skipping schema creation.)"
else
  SCHEMA_LDIF_FILE=$(mktemp)
  cat <<EOF > "$SCHEMA_LDIF_FILE"
dn: cn=custom,cn=schema,cn=config
objectClass: olcSchemaConfig
cn: custom
olcAttributeTypes: ( ${ENTERPRISE_OID}.1.1 NAME 'customMemberOf'
  DESC 'Group memberships for posixGroup (dynlist)'
  EQUALITY distinguishedNameMatch
  SYNTAX 1.3.6.1.4.1.1466.115.121.1.12 )
olcObjectClasses: ( ${ENTERPRISE_OID}.2.1 NAME 'customPerson'
  DESC 'Auxiliary class for posixGroup membership'
  SUP top AUXILIARY
  MAY ( customMemberOf ) )
EOF

  ldapadd -Y EXTERNAL -H ldapi:/// -f "$SCHEMA_LDIF_FILE"
  echo "✅ Custom schema loaded."
  rm -f "$SCHEMA_LDIF_FILE"
fi
echo ""

# --- Step 2: Load required modules (dynlist and refint) ---
echo "2. Loading 'dynlist' and 'refint' modules..."

# Function to check if a module is loaded
check_module_loaded() {
    local module_name="$1"
    ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" -s base "(objectClass=*)" olcModuleLoad 2>/dev/null | \
    grep -q "olcModuleLoad: ${module_name}"
}

# Load dynlist module if not already loaded
if check_module_loaded "dynlist"; then
  echo "   ✅ dynlist module already loaded"
else
  echo "   Loading dynlist module..."
  DYNLIST_MODULE_LDIF=$(mktemp)
  cat <<EOF > "$DYNLIST_MODULE_LDIF"
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: dynlist
EOF
  
  if ldapmodify -Y EXTERNAL -H ldapi:/// -f "$DYNLIST_MODULE_LDIF" 2>/dev/null; then
    echo "   ✅ dynlist module loaded successfully."
  else
    echo "   ⚠️  dynlist module may already be loaded or failed to load."
  fi
  rm -f "$DYNLIST_MODULE_LDIF"
fi

# Load refint module if not already loaded
if check_module_loaded "refint"; then
  echo "   ✅ refint module already loaded"
else
  echo "   Loading refint module..."
  REFINT_MODULE_LDIF=$(mktemp)
  cat <<EOF > "$REFINT_MODULE_LDIF"
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: refint
EOF
  
  if ldapmodify -Y EXTERNAL -H ldapi:/// -f "$REFINT_MODULE_LDIF" 2>/dev/null; then
    echo "   ✅ refint module loaded successfully."
  else
    echo "   ⚠️  refint module may already be loaded or failed to load."
  fi
  rm -f "$REFINT_MODULE_LDIF"
fi

echo "✅ Module loading phase complete."
echo ""

# --- Step 3: Configure the dynlist overlay ---
echo "3. Configuring the 'dynlist' overlay..."

# Verify dynlist module is actually loaded and available
echo "   Verifying dynlist module availability..."
if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=schema,cn=config" | grep -q "olcDlAttrSet"; then
  echo "   ⚠️  Warning: dynlist schema not found. Checking module loading..."
  
  # Force a module reload by checking what's actually loaded
  echo "   Currently loaded modules:"
  ldapsearch -Y EXTERNAL -H ldapi:/// -b "cn=module{0},cn=config" -s base "(objectClass=*)" olcModuleLoad 2>/dev/null | grep "olcModuleLoad:" || echo "   No modules found"
  
  # Try alternative module loading approach
  echo "   Attempting alternative module loading..."
  ALT_MODULE_LDIF=$(mktemp)
  cat <<EOF > "$ALT_MODULE_LDIF"
dn: cn=module{0},cn=config
changetype: modify
replace: olcModuleLoad
olcModuleLoad: dynlist
olcModuleLoad: refint
EOF
  
  if ldapmodify -Y EXTERNAL -H ldapi:/// -f "$ALT_MODULE_LDIF" 2>/dev/null; then
    echo "   ✅ Modules reloaded successfully."
  else
    echo "   ⚠️  Module reload failed, continuing anyway..."
  fi
  rm -f "$ALT_MODULE_LDIF"
fi

# Check if dynlist overlay already exists
if ldapsearch -Y EXTERNAL -H ldapi:/// -b "${DATABASE_DN}" 2>/dev/null | grep -q "olcOverlay.*dynlist"; then
  echo "   ✅ dynlist overlay already configured"
else
  echo "   Configuring dynlist overlay..."
  DYNLIST_LDIF_FILE=$(mktemp)
  # The LDAP search URI that finds a user's groups
  DYNLIST_URI="ldap:///${GROUPS_OU},${BASE_DN}?dn?sub?(&(objectClass=posixGroup)(memberUid=\$uid))"

  cat <<EOF > "$DYNLIST_LDIF_FILE"
dn: olcOverlay=dynlist,${DATABASE_DN}
objectClass: olcOverlayConfig
objectClass: olcDynListConfig
olcOverlay: dynlist
olcDlAttrSet: posixAccount customMemberOf ${DYNLIST_URI}
EOF

  if ldapadd -Y EXTERNAL -H ldapi:/// -f "$DYNLIST_LDIF_FILE" 2>/dev/null; then
    echo "   ✅ Dynlist overlay configured successfully."
  else
    echo "   ❌ Failed to configure dynlist overlay. Checking what went wrong..."
    echo "   Trying with minimal configuration..."
    
    # Try a simpler approach first
    SIMPLE_DYNLIST_LDIF=$(mktemp)
    cat <<EOF > "$SIMPLE_DYNLIST_LDIF"
dn: olcOverlay=dynlist,${DATABASE_DN}
objectClass: olcOverlayConfig
objectClass: olcDynListConfig
olcOverlay: dynlist
EOF
    
    if ldapadd -Y EXTERNAL -H ldapi:/// -f "$SIMPLE_DYNLIST_LDIF" 2>/dev/null; then
      echo "   ✅ Basic dynlist overlay created."
      
      # Now add the attribute set
      ATTRSET_LDIF=$(mktemp)
      cat <<EOF > "$ATTRSET_LDIF"
dn: olcOverlay=dynlist,${DATABASE_DN}
changetype: modify
add: olcDlAttrSet
olcDlAttrSet: posixAccount customMemberOf ${DYNLIST_URI}
EOF
      
      if ldapmodify -Y EXTERNAL -H ldapi:/// -f "$ATTRSET_LDIF" 2>/dev/null; then
        echo "   ✅ Dynlist attribute set configured."
      else
        echo "   ❌ Failed to add attribute set. Manual configuration may be needed."
      fi
      rm -f "$ATTRSET_LDIF"
    else
      echo "   ❌ Failed to create basic dynlist overlay."
    fi
    rm -f "$SIMPLE_DYNLIST_LDIF"
  fi
  rm -f "$DYNLIST_LDIF_FILE"
fi
echo ""

# --- Step 4: Configure the refint overlay ---
echo "4. Configuring the 'refint' overlay for data integrity..."

# Check if refint overlay already exists
if ldapsearch -Y EXTERNAL -H ldapi:/// -b "${DATABASE_DN}" | grep -q "olcOverlay: refint"; then
  echo "   (refint overlay already configured, skipping)"
else
  REFINT_LDIF_FILE=$(mktemp)
  cat <<EOF > "$REFINT_LDIF_FILE"
dn: olcOverlay=refint,${DATABASE_DN}
objectClass: olcRefintConfig
olcOverlay: refint
olcRefintAttribute: member uniqueMember manager owner
EOF

  ldapadd -Y EXTERNAL -H ldapi:/// -f "$REFINT_LDIF_FILE"
  echo "✅ Refint overlay configured."
  rm -f "$REFINT_LDIF_FILE"
fi
echo ""

# --- Final Instructions ---
echo "---------------------------------------------------------"
echo "🎉 Configuration complete!"
echo ""
echo "NEXT STEPS:"
echo "1. Modify your user entries to include the new auxiliary class."
echo "   You only need to do this once per user."
echo ""
echo "   Example LDIF ('modify_user.ldif'):"
echo "   ---------------------------------"
echo "   dn: uid=someuser,ou=people,${BASE_DN}"
echo "   changetype: modify"
echo "   add: objectClass"
echo "   objectClass: customPerson"
echo "   ---------------------------------"
echo "   Command: ldapmodify -x -D 'cn=admin,${BASE_DN}' -W -f modify_user.ldif"
echo ""
echo "2. Verify the setup by searching for a user who is in a posixGroup:"
echo "   ldapsearch -x -b 'uid=someuser,ou=people,${BASE_DN}' '(objectClass=*)' customMemberOf"
echo ""