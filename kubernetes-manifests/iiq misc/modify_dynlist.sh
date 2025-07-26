#!/bin/bash
set -e

BASEDN="ou=groups,dc=sailpoint,dc=demo"
PEOPLEDN="ou=people,dc=sailpoint,dc=demo"
DB_INDEX="{1}mdb"
TMP=$(mktemp -d)

echo "Step 1: Adding auxiliary posixGroup schema..."
cat > "$TMP/schema.ldif" <<EOF
dn: cn=nis-aux,cn=schema,cn=config
changetype: modify
add: olcObjectClasses
olcObjectClasses: ( 1.3.6.1.4.1.4203.666.1 NAME 'auxPosixGroup' DESC 'Aux posixGroup' AUXILIARY MUST ( cn \$ gidNumber ) MAY ( memberUid \$ member \$ description ) )
EOF
ldapmodify -Y EXTERNAL -H ldapi:/// -f "$TMP/schema.ldif"

echo "Step 2: Loading memberof and refint overlays..."
cat > "$TMP/overlay.ldif" <<EOF
dn: cn=module{0},cn=config
changetype: modify
add: olcModuleLoad
olcModuleLoad: memberof.la
olcModuleLoad: refint.la

dn: olcOverlay=memberof,olcDatabase=$DB_INDEX,cn=config
objectClass: olcOverlayConfig
objectClass: olcMemberOf
olcOverlay: memberof
olcMemberOfRefInt: TRUE
olcMemberOfGroupOC: groupOfNames
olcMemberOfMemberAD: member
olcMemberOfMemberOfAD: memberOf

dn: olcOverlay=refint,olcDatabase=$DB_INDEX,cn=config
objectClass: olcOverlayConfig
objectClass: olcRefintConfig
olcOverlay: refint
olcRefintAttribute: member memberOf
EOF
ldapadd -Y EXTERNAL -H ldapi:/// -f "$TMP/overlay.ldif"

echo "Step 3: Generating groupOfNames sync LDIF..."
cat > "$TMP/resolve_uids.py" <<'PY'
#!/usr/bin/env python3
import sys
from ldap3 import Server, Connection, ALL
uids=sys.argv[1].split(',')
conn=Connection(Server('ldap://localhost', get_info=ALL), auto_bind=True)
dns=[conn.search(''"$PEOPLEDN"'' , f'(uid={uid})', attributes=['dn']) and conn.entries[0].entry_dn for uid in uids]
print(','.join([dn for dn in dns if dn]))
PY
chmod +x "$TMP/resolve_uids.py"

cat > "$TMP/sync.ldif" <<EOF
EOF

ldapsearch -x -LLL -b "$BASEDN" "(objectClass=auxPosixGroup)" cn memberUid gidNumber | \
awk '/^cn: /{cn=$2} /^memberUid: /{uids=(uids==""?$2:uids","$2)} /^gidNumber: /{gid=$2} /^$/{if(cn!=""){print cn","uids","gid}; cn="";uids="";gid=""}}' | \
while IFS=, read CN UIDS GID; do
  dns=$("$TMP/resolve_uids.py" "$UIDS")
  IFS=',' read -ra MEMBERS <<< "$dns"
  echo "dn: cn=$CN,$BASEDN" >> "$TMP/sync.ldif"
  echo "changetype: modify" >> "$TMP/sync.ldif"
  echo "add: objectClass" >> "$TMP/sync.ldif"
  echo "objectClass: groupOfNames" >> "$TMP/sync.ldif"
  echo "-" >> "$TMP/sync.ldif"
  echo "replace: member" >> "$TMP/sync.ldif"
  for m in "${MEMBERS[@]}"; do echo "member: $m"; done >> "$TMP/sync.ldif"
  echo "" >> "$TMP/sync.ldif"
done

echo "Applying sync LDIF..."
ldapmodify -Y EXTERNAL -H ldapi:/// -f "$TMP/sync.ldif"

echo "Cleanup"
rm -rf "$TMP"
echo "Done. GroupOfNames synced, overlays enabled, users will now have memberOf populated."
