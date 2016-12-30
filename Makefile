VERSION ?= 1.1.0

default: build

clean:
	docker rmi bborbe/openldap:$(VERSION)

build:
	docker build --build-arg VERSION=$(VERSION) --no-cache --rm=true -t bborbe/openldap:$(VERSION) .

run:
	docker run \
  -p 389:389 -p 636:636 \
  -e LDAP_SECRET='S3CR3T' \
  -e LDAP_SUFFIX='dc=example,dc=com' \
  -e LDAP_ROOTDN='cn=root,dc=example,dc=com' \
  bborbe/openldap:$(VERSION)

shell:
	docker run -i -t bborbe/openldap:$(VERSION) /bin/bash

upload:
	docker push bborbe/openldap:$(VERSION)
