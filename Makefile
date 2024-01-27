VERSION ?= 1.3.0
REGISTRY ?= docker.io
IMAGE ?= bborbe/openldap
default: build

clean:
	docker rmi $(REGISTRY)/$(IMAGE):$(VERSION)

build:
	docker build --no-cache --rm=true --platform=linux/amd64 -t $(REGISTRY)/$(IMAGE):$(VERSION) .

upload:
	docker push $(REGISTRY)/$(IMAGE):$(VERSION)

run:
	docker run \
  -p 389:389 -p 636:636 \
  -e LDAP_SECRET='S3CR3T' \
  -e LDAP_SUFFIX='dc=example,dc=com' \
  -e LDAP_ROOTDN='cn=root,dc=example,dc=com' \
  $(REGISTRY)/$(IMAGE):$(VERSION)

shell:
	docker run -i -t $(REGISTRY)/$(IMAGE):$(VERSION) /bin/bash
