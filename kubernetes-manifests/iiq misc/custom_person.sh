#!/bin/sh

BASE_DN="dc=sailpoint,dc=demo"
LDIF_FILE="modify_users.ldif"

# Clean up any existing LDIF file
rm -f "$LDIF_FILE"

echo "🚀 Adding customPerson objectClass to all users in $BASE_DN"
echo "Using SASL EXTERNAL authentication"
echo "--------------------------------------------------------"

# First, let's check a few existing users to understand the DN format
echo "1. Analyzing existing user entries..."
PEOPLE_BASE="ou=people,$BASE_DN"

# Get a sample of user entries with their full information
echo "Sample user entries:"
ldapsearch -Y EXTERNAL -H ldapi:/// -b "$PEOPLE_BASE" -s one \
  "(|(objectClass=inetOrgPerson)(objectClass=posixAccount)(objectClass=person))" \
  dn objectClass 2>/dev/null | head -20

echo ""
echo "2. Processing users one by one..."

USER_COUNT=0
FAILED_COUNT=0

# Create a temporary file to store user DNs properly
TEMP_DNS=$(mktemp)

# Extract user DNs more carefully
ldapsearch -Y EXTERNAL -H ldapi:/// -b "$PEOPLE_BASE" -s one \
  "(|(objectClass=inetOrgPerson)(objectClass=posixAccount)(objectClass=person))" \
  dn 2>/dev/null | grep "^dn: " | sed 's/^dn: //' > "$TEMP_DNS"

if [ ! -s "$TEMP_DNS" ]; then
  echo "❌ No user entries found in $PEOPLE_BASE"
  rm -f "$TEMP_DNS"
  exit 1
fi

echo "Found $(wc -l < "$TEMP_DNS") potential user entries"
echo ""

# Process each DN individually
while IFS= read -r USER_DN; do
  # Skip empty lines
  if [ -z "$USER_DN" ]; then
    continue
  fi
  
  echo "Processing: $USER_DN"
  
  # Verify the DN exists and get its objectClasses
  if ! ldapsearch -Y EXTERNAL -H ldapi:/// -b "$USER_DN" -s base "(objectClass=*)" objectClass 2>/dev/null | grep -q "objectClass:"; then
    echo "  ❌ Cannot access entry: $USER_DN"
    FAILED_COUNT=$((FAILED_COUNT + 1))
    continue
  fi
  
  # Check if user already has customPerson objectClass
  if ldapsearch -Y EXTERNAL -H ldapi:/// -b "$USER_DN" -s base "(objectClass=customPerson)" dn 2>/dev/null | grep -q "^dn:"; then
    echo "  ⏭️  Already has customPerson objectClass"
    continue
  fi
  
  # Try to add the objectClass to this specific user
  SINGLE_USER_LDIF=$(mktemp)
  cat <<EOF > "$SINGLE_USER_LDIF"
dn: $USER_DN
changetype: modify
add: objectClass
objectClass: customPerson
EOF
  
  echo "  🔧 Adding customPerson objectClass..."
  if ldapmodify -Y EXTERNAL -H ldapi:/// -f "$SINGLE_USER_LDIF" 2>/dev/null; then
    echo "  ✅ Successfully modified"
    USER_COUNT=$((USER_COUNT + 1))
  else
    echo "  ❌ Failed to modify - checking details..."
    
    # Show the actual error
    echo "  Error details:"
    ldapmodify -Y EXTERNAL -H ldapi:/// -f "$SINGLE_USER_LDIF" 2>&1 | sed 's/^/    /'
    
    # Check if the DN is valid by trying to read it
    echo "  Verifying DN accessibility:"
    if ldapsearch -Y EXTERNAL -H ldapi:/// -b "$USER_DN" -s base "(objectClass=*)" dn 2>&1 | grep -q "^dn:"; then
      echo "    ✅ DN is accessible"
    else
      echo "    ❌ DN is not accessible:"
      ldapsearch -Y EXTERNAL -H ldapi:/// -b "$USER_DN" -s base "(objectClass=*)" dn 2>&1 | sed 's/^/      /'
    fi
    
    FAILED_COUNT=$((FAILED_COUNT + 1))
  fi
  
  rm -f "$SINGLE_USER_LDIF"
  echo ""
  
done < "$TEMP_DNS"

# Cleanup
rm -f "$TEMP_DNS" "$LDIF_FILE"

echo "=========================================="
echo "📊 Summary:"
echo "   ✅ Successfully modified: $USER_COUNT users"
echo "   ❌ Failed: $FAILED_COUNT users"
echo ""

if [ "$USER_COUNT" -gt 0 ]; then
  echo "🧪 Verification: Users now with customPerson objectClass..."
  ldapsearch -Y EXTERNAL -H ldapi:/// -b "$BASE_DN" "(objectClass=customPerson)" dn | grep "^dn:" | head -10
  
  echo ""
  echo "🎉 Process complete!"
  echo "   You can now test dynlist functionality with one of these users:"
  echo "   ldapsearch -Y EXTERNAL -H ldapi:/// -b 'USER_DN_HERE' '(objectClass=*)' customMemberOf"
else
  echo "❌ No users were successfully modified."
  echo ""
  echo "🔍 Troubleshooting suggestions:"
  echo "   1. Check if the customPerson objectClass schema is properly loaded"
  echo "   2. Verify LDAP permissions for modifying user entries"
  echo "   3. Check LDAP server logs for more detailed error information"
fi