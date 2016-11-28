default: build

clean:
	docker rmi bborbe/openldap

build:
	docker build --no-cache --rm=true -t bborbe/openldap .

run:
	docker run \
  -p 389:389 -p 636:636 \
  -e LDAP_SECRET='S3CR3T' \
  -e LDAP_SUFFIX='dc=example,dc=com' \
  -e LDAP_ROOTDN='cn=admin,dc=example,dc=com' \
  bborbe/openldap:latest

shell:
	docker run -i -t bborbe/openldap:latest /bin/bash

upload:
	docker push bborbe/openldap
