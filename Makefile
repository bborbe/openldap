VERSION ?= latest
REGISTRY ?= docker.io

default: build

clean:
	docker rmi $(REGISTRY)/bborbe/openldap:$(VERSION)

build:
	docker build --no-cache --rm=true -t $(REGISTRY)/bborbe/openldap:$(VERSION) .

run:
	docker run \
  -p 389:389 -p 636:636 \
  -e LDAP_SECRET='S3CR3T' \
  -e LDAP_SUFFIX='dc=example,dc=com' \
  -e LDAP_ROOTDN='cn=root,dc=example,dc=com' \
  $(REGISTRY)/bborbe/openldap:$(VERSION)

shell:
	docker run -i -t $(REGISTRY)/bborbe/openldap:$(VERSION) /bin/bash

upload:
	docker push $(REGISTRY)/bborbe/openldap:$(VERSION)
