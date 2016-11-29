# Openldap Dockerfile

Alpine based Slapd Ldap-Server

## Run

```
docker run \
-p 389:389 -p 636:636 \
-e LDAP_SECRET='S3CR3T' \
-e LDAP_SUFFIX='dc=my-domain,dc=com' \
-e LDAP_ROOTDN='cn=Manager,dc=my-domain,dc=com' \
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

ldapadd -x -W -D "cn=admin,dc=example,dc=com" -f base.ldif

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
```

ldapadd -x -W -D "cn=admin,dc=example,dc=com" -f user.ldif

## Set Password for user

ldappasswd -s S3CR3T -W -D "cn=admin,dc=example,dc=com" -x "uid=bb,ou=users,dc=example,dc=com"

## Copyright and license

    Copyright (c) 2016, Benjamin Borbe <bborbe@rocketnews.de>
    All rights reserved.
    
    Redistribution and use in source and binary forms, with or without
    modification, are permitted provided that the following conditions are
    met:
    
       * Redistributions of source code must retain the above copyright
         notice, this list of conditions and the following disclaimer.
       * Redistributions in binary form must reproduce the above
         copyright notice, this list of conditions and the following
         disclaimer in the documentation and/or other materials provided
         with the distribution.

    THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
    "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
    LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
    A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
    OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
    SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
    LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
    DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
    THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
    (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
    OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
