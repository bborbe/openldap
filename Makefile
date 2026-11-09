VERSION ?= 1.3.0
REGISTRY ?= docker.io
IMAGE ?= bborbe/openldap
default: build

# Container-safe gates. The dark-factory pipeline runs `make precommit` as its
# authoritative validation command and `make test` as its iteration command, and
# neither may shell out to Docker — the YOLO container has no daemon. Both run
# before the cluster build arm exists, so they tolerate a missing hack/ tree.
.PHONY: precommit test

precommit:
	@for f in hack/*.sh; do [ -e "$$f" ] || continue; bash -n "$$f"; done
	@make -n build >/dev/null

test:
	@echo "no unit tests — this repo ships a Dockerfile and build scripts only"

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
