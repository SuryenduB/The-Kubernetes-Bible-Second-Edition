#!/bin/sh

BASE_DN="dc=sailpoint,dc=demo"
TEST_USER="cn=aaron.segers@primarygrocers.corp,ou=people,dc=sailpoint,dc=demo"
GROUPS_OU="ou=groups"

echo "🔍 Debugging dynlist configuration and group membership"
echo "======================================================"

echo "1. Checking dynlist overlay configuration..."
echo ""
echo "Current dynlist configuration:"
ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={1}mdb,cn=config" \
  "(objectClass=olcDynListConfig)" olcDlAttrSet 2>/dev/null

echo ""
echo "2. Analyzing test user: $TEST_USER"
echo ""
echo "User attributes:"
ldapsearch -Y EXTERNAL -H ldapi:/// -b "$TEST_USER" -s base "(objectClass=*)" \
  dn cn uid mail objectClass 2>/dev/null

echo ""
echo "3. Looking for posixGroups..."
echo ""
echo "Groups in $GROUPS_OU,$BASE_DN:"
if ldapsearch -Y EXTERNAL -H ldapi:/// -b "$GROUPS_OU,$BASE_DN" -s one \
  "(objectClass=posixGroup)" dn cn memberUid 2>/dev/null | grep -q "^dn:"; then
  
  ldapsearch -Y EXTERNAL -H ldapi:/// -b "$GROUPS_OU,$BASE_DN" -s one \
    "(objectClass=posixGroup)" dn cn memberUid 2>/dev/null | head -30
else
  echo "❌ No posixGroups found in $GROUPS_OU,$BASE_DN"
  echo ""
  echo "Searching entire tree for posixGroups..."
  ldapsearch -Y EXTERNAL -H ldapi:/// -b "$BASE_DN" \
    "(objectClass=posixGroup)" dn cn memberUid 2>/dev/null | head -30
fi

echo ""
echo "4. Checking if test user is in any groups..."
echo ""

# Extract uid from test user
USER_UID=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b "$TEST_USER" -s base "(objectClass=*)" uid 2>/dev/null | grep "^uid:" | sed 's/^uid: //')
USER_CN=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b "$TEST_USER" -s base "(objectClass=*)" cn 2>/dev/null | grep "^cn:" | sed 's/^cn: //')

echo "User uid: $USER_UID"
echo "User cn: $USER_CN"

if [ -n "$USER_UID" ]; then
  echo ""
  echo "Groups where memberUid=$USER_UID:"
  ldapsearch -Y EXTERNAL -H ldapi:/// -b "$BASE_DN" \
    "(&(objectClass=posixGroup)(memberUid=$USER_UID))" dn cn memberUid 2>/dev/null
else
  echo "❌ User has no uid attribute!"
fi

if [ -n "$USER_CN" ]; then
  echo ""
  echo "Groups where memberUid=$USER_CN:"
  ldapsearch -Y EXTERNAL -H ldapi:/// -b "$BASE_DN" \
    "(&(objectClass=posixGroup)(memberUid=$USER_CN))" dn cn memberUid 2>/dev/null
fi

echo ""
echo "5. Testing the dynlist URI manually..."
echo ""

# Get the current dynlist URI
CURRENT_URI=$(ldapsearch -Y EXTERNAL -H ldapi:/// -b "olcDatabase={1}mdb,cn=config" \
  "(objectClass=olcDynListConfig)" olcDlAttrSet 2>/dev/null | \
  grep "olcDlAttrSet:" | sed 's/.*ldap:\/\/\///')

echo "Current dynlist URI: $CURRENT_URI"

if [ -n "$CURRENT_URI" ]; then
  # Extract the search base and filter from the URI
  URI_BASE=$(echo "$CURRENT_URI" | cut -d'?' -f1)
  URI_FILTER=$(echo "$CURRENT_URI" | cut -d'?' -f4)
  
  echo "URI search base: $URI_BASE"
  echo "URI filter: $URI_FILTER"
  
  if [ -n "$USER_UID" ]; then
    # Replace %uid with actual uid
    ACTUAL_FILTER=$(echo "$URI_FILTER" | sed "s/%uid/$USER_UID/g" | sed 's/\\$/$/g')
    echo "Filter with uid substituted: $ACTUAL_FILTER"
    
    echo ""
    echo "Manual search with this filter:"
    ldapsearch -Y EXTERNAL -H ldapi:/// -b "$URI_BASE" "$ACTUAL_FILTER" dn 2>/dev/null
  fi
fi

echo ""
echo "6. Checking alternative group membership patterns..."
echo ""

# Check for other common group membership attributes
echo "Groups with 'member' attribute containing user DN:"
ldapsearch -Y EXTERNAL -H ldapi:/// -b "$BASE_DN" \
  "(member=$TEST_USER)" dn cn member 2>/dev/null | head -20

echo ""
echo "Groups with 'uniqueMember' attribute:"
ldapsearch -Y EXTERNAL -H ldapi:/// -b "$BASE_DN" \
  "(uniqueMember=$TEST_USER)" dn cn uniqueMember 2>/dev/null | head -20

echo ""
echo "7. Recommendations:"
echo "=================="

if [ -z "$USER_UID" ]; then
  echo "❌ PROBLEM: User has no 'uid' attribute!"
  echo "   Solutions:"
  echo "   1. Add a uid attribute to the user"
  echo "   2. Modify the dynlist URI to use 'cn' instead of 'uid'"
  echo "   3. Use a different attribute for matching"
  echo ""
fi

echo "🔧 Possible fixes:"
echo "1. If user has no uid, add one:"
echo "   dn: $TEST_USER"
echo "   changetype: modify"
echo "   add: uid"
echo "   uid: some-username"
echo ""
echo "2. Or modify dynlist to use cn instead of uid:"
echo "   URI: ldap:///$GROUPS_OU,$BASE_DN?dn?sub?(&(objectClass=posixGroup)(memberUid=\$cn))"
echo ""
echo "3. Create a test group with the user as member:"
echo "   dn: cn=testgroup,$GROUPS_OU,$BASE_DN"
echo "   objectClass: posixGroup"
echo "   cn: testgroup"
echo "   gidNumber: 10001"
echo "   memberUid: $USER_UID"