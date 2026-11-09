VERSION ?= 1.3.0
REGISTRY ?= docker.io
IMAGE ?= bborbe/openldap
BUILD_TARGET ?= local

# Cluster-arm inputs. Only read when BUILD_TARGET is not `local`.
# REPO_URL is https on purpose: the Job's init container clones anonymously and
# carries no SSH key.
REPO_URL ?= https://github.com/bborbe/openldap.git
REF ?= HEAD
NAMESPACE ?= build
DOCKERFILE ?= Dockerfile
PUSH ?= true
PUSH_SECRET ?= buildkit-push
BUILD_TIMEOUT ?= 3600

default: build

# Container-safe gates. The dark-factory pipeline runs `make precommit` as its
# authoritative validation command and `make test` as its iteration command, and
# neither may shell out to Docker — the YOLO container has no daemon.
.PHONY: precommit test build upload clean run shell

precommit:
	@for f in hack/*.sh; do [ -e "$$f" ] || continue; bash -n "$$f"; done
	@make -n build >/dev/null

test:
	@echo "no unit tests — this repo ships a Dockerfile and build scripts only"

ifeq ($(BUILD_TARGET),local)

# The local arm is unchanged: same docker build arguments, same tag, image left
# in the local Docker store. It never touches a cluster and needs no kubeconfig.
build:
	docker build --no-cache --rm=true --platform=linux/amd64 -t $(REGISTRY)/$(IMAGE):$(VERSION) .

upload:
	docker push $(REGISTRY)/$(IMAGE):$(VERSION)

clean:
	docker rmi $(REGISTRY)/$(IMAGE):$(VERSION)

else

# The cluster arm builds and pushes inside the pod, so nothing was produced on
# the invoking host. A plain `docker rmi` here would delete the unrelated local
# $(VERSION) image.
#
# The defaulted-VERSION guard sits inside this branch only: VERSION is assigned
# in this file, so $(origin VERSION) reads `file` on every bare `make build` and
# a parse-time guard would refuse the local arm instead.
build:
ifeq ($(origin VERSION),file)
	$(error the cluster arm needs an explicit VERSION; pass VERSION=<tag> on the make command line)
else
	BUILD_TARGET='$(BUILD_TARGET)' \
	NAMESPACE='$(NAMESPACE)' \
	REPO_URL='$(REPO_URL)' \
	REF='$(REF)' \
	TAG='$(VERSION)' \
	DOCKERFILE='$(DOCKERFILE)' \
	IMAGE='$(REGISTRY)/$(IMAGE)' \
	DOCKER_REGISTRY='$(REGISTRY)' \
	PUSH='$(PUSH)' \
	PUSH_SECRET='$(PUSH_SECRET)' \
	TIMEOUT='$(BUILD_TIMEOUT)' \
	hack/build-cluster.sh
endif

upload:
	@echo "BUILD_TARGET=$(BUILD_TARGET): upload is a no-op for a cluster target — nothing to do"

clean:
	@echo "BUILD_TARGET=$(BUILD_TARGET): clean is a no-op for a cluster target — nothing to do"

endif

run:
	docker run \
  -p 389:389 -p 636:636 \
  -e LDAP_SECRET='S3CR3T' \
  -e LDAP_SUFFIX='dc=example,dc=com' \
  -e LDAP_ROOTDN='cn=root,dc=example,dc=com' \
  $(REGISTRY)/$(IMAGE):$(VERSION)

shell:
	docker run -i -t $(REGISTRY)/$(IMAGE):$(VERSION) /bin/bash
