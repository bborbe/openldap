# Openldap

Alpine based Slapd Ldap-Server

## Run

```
docker run \
-p 389:389 -p 636:636 \
-e LDAP_SECRET='S3CR3T' \
-e LDAP_SUFFIX='dc=example,dc=com' \
-e LDAP_ROOTDN='cn=root,dc=example,dc=com' \
bborbe/openldap:latest
```

## Setup Ldap structur

cat > base.ldif

```
dn: dc=example,dc=com
dc: example
objectClass: dcObject
objectClass: organization
o: Example

dn: ou=users,dc=example,dc=com
ou: users
objectClass: organizationalUnit
objectClass: top

dn: ou=groups,dc=example,dc=com
ou: groups
objectClass: organizationalUnit
objectClass: top
```

ldapadd -x -W -D "cn=root,dc=example,dc=com" -f base.ldif

## Create user

cat > user.ldif

```
dn: uid=bborbe,ou=users,dc=example,dc=com
objectClass: inetOrgPerson
objectClass: organizationalPerson
objectClass: person
objectClass: top
uid: bborbe
cn: Benjamin Borbe
givenName: Benjamin
sn: Borbe
mail: benjamin.borbe@gmail.com
```

ldapadd -x -W -D "cn=root,dc=example,dc=com" -f user.ldif

## Set Password for user

ldappasswd -s S3CR3T -W -D "cn=root,dc=example,dc=com" -x "uid=bborbe,ou=users,dc=example,dc=com"

## Create group

cat > group-employees.ldif

```
dn: ou=employees,ou=groups,dc=example,dc=com
objectClass: groupOfNames
objectClass: top
ou: employees
cn: Employees
member: uid=bborbe,ou=users,dc=example,dc=com
```

ldapadd -x -W -D "cn=root,dc=example,dc=com" -f group-employees.ldif

cat > group-admins.ldif

```
dn: ou=admins,ou=groups,dc=example,dc=com
objectClass: groupOfNames
objectClass: top
ou: admins
cn: Admins
member: uid=bborbe,ou=users,dc=example,dc=com
```

ldapadd -x -W -D "cn=root,dc=example,dc=com" -f group-admins.ldif

