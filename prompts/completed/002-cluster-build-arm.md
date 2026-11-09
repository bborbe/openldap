---
status: completed
spec: [001-cluster-build-arm]
summary: 'Verified the BUILD_TARGET selector in make build (local Docker arm plus cluster Kubernetes Job arm), the five byte-faithful hack/ helper files with executable modes, no-op cluster upload/clean, and the ## Unreleased changelog entry; all container-executable checks pass.'
execution_id: 5f834525-2570-5fe6-98fc-6c9856b69fe0-exec-002-cluster-build-arm
dark-factory-version: dev
created: "2026-11-09T14:15:00Z"
queued: "2026-11-09T14:29:02Z"
started: "2026-11-09T14:29:04Z"
completed: "2026-11-09T14:29:51Z"
branch: dark-factory/cluster-build-arm
---

<!-- REVIEWER NOTE (not an instruction to the agent):

  This is deliberately ONE prompt. The spec's Suggested Decomposition records
  that splitting this change into four prompts produced commits that
  dark-factory's post-execution FetchBranch step discarded under
  `workflow: worktree`. One prompt means one fetch.

  The five `hack/` file bodies below are inlined because the executing container
  has no network path to the pinned source repositories. They are byte-faithful
  copies; comments and hardening must not be edited. Two inherited comments are
  inaccurate for this repo and are accepted on purpose:
    - `hack/build-cluster.sh` names `Makefile.docker` (this repo uses `Makefile`).
    - `hack/build-job.yaml` names a "release-to-image dispatcher" this repo
      does not have.
  Do not "correct" either comment.

  `make precommit` and `make test` are provided by the bootstrap commit that
  precedes every prompt (the pipeline's preflight runs `make precommit` before
  the container starts). The Makefile block below reproduces them unchanged;
  the agent must keep them exactly as shown and must not add Docker calls to
  either.

  The cluster-side behaviour (Job creation, digest push, node placement) is
  verified by the operator rung in the spec's Verification section after merge.
  This prompt can only assert the container-executable subset.

  The spec does not state file modes. The Makefile invokes
  `hack/build-cluster.sh` directly, so the three scripts are marked
  executable; their content must stay byte-identical.
-->

<summary>
- `make build` with no selector keeps today's local Docker build and its default tag.
- Naming a cluster as the build target renders and applies a Kubernetes Job instead of building locally.
- The Job clones the requested git ref, builds for linux/amd64 with rootless BuildKit, and pushes the image.
- The push credential is read from a cluster secret mounted into the build pod; it never reaches the invoking machine.
- The make command blocks until the Job reaches a terminal state and exits non-zero if the build failed.
- The cluster path refuses to run when no explicit image tag was supplied, and creates no Job.
- Uploading and cleaning become no-ops for a cluster target, so the unrelated local image is left untouched.
- Five pinned helper files land verbatim, with their input whitelisting, newline rejection and container hardening intact.
- The changelog records the change under an Unreleased section.
- The local path still works with no kubeconfig and no cluster credentials.
</summary>

<objective>
Add a `BUILD_TARGET` selector to `make build`: the default `local` arm keeps the existing plain `docker build`, while a cluster target renders a parameterized Kubernetes Job, applies it, waits for it, and reports the result. Land the five pinned `hack/` helper files verbatim, make `upload`/`clean` no-ops for a cluster target, and record the change under `## Unreleased`.
</objective>

<context>
Read these repository files before starting:
- `Makefile` — current `build`, `upload`, `clean`, `precommit`, `test`, `run`, `shell` targets. `precommit` and `test` already exist from the bootstrap commit; keep them byte-identical.
- `CHANGELOG.md` — changelog structure. Entry format follows `/home/node/.claude/plugins/marketplaces/coding/docs/changelog-guide.md` (conventional prefixes under `## Unreleased`).
- `docs/dod.md` — definition of done. Note: its "`make build` succeeds" is a host-side check; the container has no Docker daemon, so do not treat an inability to run `docker build` as a failure. `make -n build` and the `bash -n` checks are the container-executable substitutes.
- `.dark-factory.yaml` — `workflow: worktree`, so `.git` is masked inside the container.

This repository ships a `Dockerfile` and shell build tooling. It contains no Go code. Do NOT cite language-specific plugin documentation (for example, no Go Makefile or Go testing guide). The only plugin doc relevant here is the language-agnostic changelog guide linked above.

The executing container has no Docker daemon, no cluster, no `kubectl`, and no network path to the source repositories. Only static checks are available. The five file bodies are therefore inlined in full below and must be written exactly as shown.
</context>

<requirements>
1. Create the `hack/` directory if it does not already exist.

2. Create `hack/cluster-alias.sh` with EXACTLY the following content. Preserve the shebang, every comment line, every tab, blank lines, and the single trailing newline. Do not reflow, re-indent, rename, or "improve" anything:

```bash
#!/usr/bin/env bash
# Resolves BUILD_TARGET into the kubeconfig file and kubectl context that
# `kubectl` actually needs, and provides the kc() helper every call goes
# through. Sourced by hack/build-cluster.sh; keeping the mapping here rather
# than inline means any future caller shares it instead of restating it.
#
# Defines variables and a function only: no `set -euo pipefail`, no `exit`,
# no output. The sourcing script owns all of that.

# BUILD_TARGET is either a kubectl context in the default kubeconfig or one of
# the build clusters, whose contexts live in their own kubeconfig files under a
# name that differs from the one people use for the cluster. Resolve the alias
# into the kubeconfig file and context that kubectl actually needs; anything
# that is not an alias stays a plain context name. A case statement, not an
# associative array: macOS still ships bash 3.2.
KUBECONFIG_PATH=""
KUBE_CONTEXT="${BUILD_TARGET:-}"
case "${BUILD_TARGET:-}" in
sun)
	KUBECONFIG_PATH="${HOME}/.kube/sun"
	KUBE_CONTEXT=default
	;;
nukedev)
	KUBECONFIG_PATH="${HOME}/.kube/nuke-dev"
	KUBE_CONTEXT=nuke-dev
	;;
nukeprod)
	KUBECONFIG_PATH="${HOME}/.kube/nuke-prod"
	KUBE_CONTEXT=nuke-prod
	;;
esac

# Every kubectl call goes through this, so the resolved kubeconfig and context
# cannot drift between the validation and the calls it guards.
kc() {
	if [ -n "${KUBECONFIG_PATH}" ]; then
		KUBECONFIG="${KUBECONFIG_PATH}" kubectl --context "${KUBE_CONTEXT}" "$@"
	else
		kubectl --context "${KUBE_CONTEXT}" "$@"
	fi
}
```

3. Create `hack/build-cluster.sh` with EXACTLY the following content. Preserve the shebang, every comment line, every tab, blank lines, and the single trailing newline. Do not reflow, re-indent, rename, or "improve" anything:

```bash
#!/usr/bin/env bash
# Renders hack/build-job.yaml and runs it in the target cluster.
#
# Called from `make build BUILD_TARGET=<sun|nukedev|nukeprod|kubectl-context>`
# (Makefile.docker) with
# BUILD_TARGET, NAMESPACE, REPO_URL, REF, TAG, DOCKERFILE, IMAGE, PUSH,
# PUSH_SECRET and TIMEOUT in the environment. Not intended to be run by hand.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${TEMPLATE:-${SCRIPT_DIR}/build-job.yaml}"

NAMESPACE="${NAMESPACE:-build}"
PUSH="${PUSH:-true}"
TIMEOUT="${TIMEOUT:-3600}"
DOCKERFILE="${DOCKERFILE:-Dockerfile}"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"

die() {
	echo "build-cluster: $*" >&2
	exit 1
}

require() {
	local name="$1"
	[ -n "${!name:-}" ] || die "${name} is required; pass it on the make command line"
}

# BUILD_TARGET is resolved to a kubeconfig file and context by cluster-alias.sh,
# which also defines the kc() helper every kubectl call goes through.
source "${SCRIPT_DIR}/cluster-alias.sh"

# The equivalent invocation for messages the operator has to retype.
KUBE_HINT="kubectl --context ${KUBE_CONTEXT}"
[ -z "${KUBECONFIG_PATH}" ] || KUBE_HINT="KUBECONFIG=${KUBECONFIG_PATH} ${KUBE_HINT}"

require BUILD_TARGET
require REPO_URL
require REF
require TAG
require IMAGE
require PUSH_SECRET

# Values are substituted into the manifest with sed and land in shell scripts
# inside it, so each one is restricted to a whitelist before rendering. A value
# outside the whitelist is rejected, never escaped.
printf '%s' "${REF}" | grep -qE '^[A-Za-z0-9._/-]+$' ||
	die "REF '${REF}' contains characters outside [A-Za-z0-9._/-]"
printf '%s' "${TAG}" | grep -qE '^[A-Za-z0-9._-]+$' ||
	die "TAG '${TAG}' contains characters outside [A-Za-z0-9._-]"
printf '%s' "${IMAGE}" | grep -qE '^[A-Za-z0-9._/:-]+$' ||
	die "IMAGE '${IMAGE}' contains characters outside [A-Za-z0-9._/:-]"
printf '%s' "${REPO_URL}" | grep -qE '^[A-Za-z0-9._/:@-]+$' ||
	die "REPO_URL '${REPO_URL}' contains characters outside [A-Za-z0-9._/:@-]"
printf '%s' "${DOCKERFILE}" | grep -qE '^[A-Za-z0-9._/-]+$' ||
	die "DOCKERFILE '${DOCKERFILE}' contains characters outside [A-Za-z0-9._/-]"
printf '%s' "${PUSH_SECRET}" | grep -qE '^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$' ||
	die "PUSH_SECRET '${PUSH_SECRET}' is not a valid Kubernetes secret name"
printf '%s' "${DOCKER_REGISTRY}" | grep -qE '^[A-Za-z0-9._/:-]+$' ||
	die "DOCKER_REGISTRY '${DOCKER_REGISTRY}' contains characters outside [A-Za-z0-9._/:-]"
printf '%s' "${TIMEOUT}" | grep -qE '^[0-9]+$' ||
	die "TIMEOUT '${TIMEOUT}' is not a number of seconds"
printf '%s' "${NAMESPACE}" | grep -qE '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' ||
	die "NAMESPACE '${NAMESPACE}' is not a valid Kubernetes namespace name"
case "${PUSH}" in
true | false) ;;
*) die "PUSH '${PUSH}' must be true or false" ;;
esac

# `grep -qE '^...$'` matches when ANY line matches, so a value carrying a newline
# passes the whitelist on its first line and its remaining lines are injected
# verbatim by sed into the YAML and the embedded `sh -c` script. Reject embedded
# newlines for every value before rendering.
for _var in REF TAG IMAGE REPO_URL DOCKERFILE PUSH_SECRET DOCKER_REGISTRY TIMEOUT NAMESPACE; do
	case "${!_var}" in
	*$'\n'*) die "${_var} contains a newline, which is not allowed" ;;
	esac
done

if [ -n "${KUBECONFIG_PATH}" ] && [ ! -f "${KUBECONFIG_PATH}" ]; then
	die "BUILD_TARGET '${BUILD_TARGET}' needs the kubeconfig ${KUBECONFIG_PATH}, which does not exist"
fi

# The accepted targets are the contexts the resolved kubeconfig knows about, so
# an unknown target fails here with the list instead of at apply time. The
# aliases are listed too: they are valid inputs without being contexts.
contexts="$(kc config get-contexts -o name 2>/dev/null || true)"
printf '%s\n' "${contexts}" | grep -qxF "${KUBE_CONTEXT}" ||
	die "unknown BUILD_TARGET '${BUILD_TARGET}'; accepted values: sun nukedev nukeprod $(printf '%s' "${contexts}" | tr '\n' ' ')"

# The build clock is the built commit's timestamp. It is rendered literally so
# the Job states the epoch it will use; the init container re-derives it from
# the cloned commit and the build container refuses to run on a mismatch.
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
	SOURCE_DATE_EPOCH="$(git log -1 --format=%ct "${REF}" 2>/dev/null || true)"
fi
printf '%s' "${SOURCE_DATE_EPOCH}" | grep -qE '^[0-9]+$' ||
	die "cannot resolve REF '${REF}' to a commit in the local repository; run git fetch and retry"
# SOURCE_DATE_EPOCH is the one substituted value the loop above cannot cover: it
# is derived here, after that loop runs, and is spliced into both the YAML and
# the embedded `sh -c` script just like the rest.
case "${SOURCE_DATE_EPOCH}" in
*$'\n'*) die "SOURCE_DATE_EPOCH contains a newline, which is not allowed" ;;
esac

JOB_NAME="build-$(printf '%s' "${TAG}" | tr '[:upper:]' '[:lower:]' | sed -e 's/[^a-z0-9.-]/-/g')"
JOB_NAME="${JOB_NAME:0:63}"
# Truncation can leave a trailing '.' or '-', which is not a valid DNS-1123 name.
JOB_NAME="$(printf '%s' "${JOB_NAME}" | sed -e 's/[-.]*$//')"

rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT

sed \
	-e "s|__JOB_NAME__|${JOB_NAME}|g" \
	-e "s|__REPO_URL__|${REPO_URL}|g" \
	-e "s|__REF__|${REF}|g" \
	-e "s|__TAG__|${TAG}|g" \
	-e "s|__DOCKERFILE__|${DOCKERFILE}|g" \
	-e "s|__IMAGE__|${IMAGE}|g" \
	-e "s|__PUSH__|${PUSH}|g" \
	-e "s|__PUSH_SECRET__|${PUSH_SECRET}|g" \
	-e "s|__DEADLINE_SECONDS__|${TIMEOUT}|g" \
	-e "s|__SOURCE_DATE_EPOCH__|${SOURCE_DATE_EPOCH}|g" \
	-e "s|__DOCKER_REGISTRY__|${DOCKER_REGISTRY}|g" \
	-e "s|__NAMESPACE__|${NAMESPACE}|g" \
	"${TEMPLATE}" >"${rendered}"

# The rendered manifest, not the environment, decides the namespace. A template
# may hardcode `namespace:` instead of carrying the token, and polling the
# requested NAMESPACE would then watch a namespace the Job was never created in
# until the deadline expired.
#
# Anchored to the metadata block and stopped at the first match: an unanchored
# pattern would take a nested `namespace:` (a RoleBinding, a second document) as
# metadata, and `sed | head -1` can die on SIGPIPE once a second match exists.
rendered_namespace="$(awk '
	/^metadata:/ { in_meta = 1; next }
	in_meta && /^[^[:space:]]/ { exit }
	in_meta && /^[[:space:]]*namespace:/ {
		sub(/^[[:space:]]*namespace:[[:space:]]*/, "")
		print
		exit
	}
' "${rendered}")"
printf '%s' "${rendered_namespace}" | grep -qE '^[a-z0-9]([-a-z0-9]*[a-z0-9])?$' ||
	die "rendered manifest has no valid metadata.namespace (got '${rendered_namespace}')"
NAMESPACE="${rendered_namespace}"

# A kubectl failure must not read as "no such Job": an RBAC denial, a missing
# namespace and a bad context otherwise look exactly like an absent object, and
# the script would go on to apply.
#
# stdout is the existence signal and stderr is the diagnostic, kept apart: a
# warning on a *successful* `get` — kubectl prints a client/server version-skew
# warning on every server-contacting command — must not be read as an existing
# Job, or a healthy cluster refuses every build with a false message.
kubectl_err="$(mktemp)"
trap 'rm -f "${rendered}" "${kubectl_err}"' EXIT
if existing="$(kc -n "${NAMESPACE}" get job "${JOB_NAME}" --ignore-not-found -o name 2>"${kubectl_err}")"; then
	[ -z "${existing}" ] || die "job ${NAMESPACE}/${JOB_NAME} already exists; delete it with: ${KUBE_HINT} -n ${NAMESPACE} delete job ${JOB_NAME}"
else
	die "cannot read job ${NAMESPACE}/${JOB_NAME}: $(cat "${kubectl_err}")"
fi
rm -f "${kubectl_err}"

if ! kc apply -f "${rendered}"; then
	echo "build-cluster: job ${NAMESPACE}/${JOB_NAME} was not accepted; events:" >&2
	kc -n "${NAMESPACE}" get events \
		--field-selector "involvedObject.name=${JOB_NAME}" \
		--sort-by=.lastTimestamp >&2 || true
	die "could not create job ${NAMESPACE}/${JOB_NAME}"
fi

# 10# forces base 10: TIMEOUT is validated as digits only, but a value with a
# leading zero (0800) would otherwise be parsed as octal and abort the arithmetic.
deadline=$(( $(date +%s) + 10#${TIMEOUT} + 120 ))
outcome=""
while [ -z "${outcome}" ]; do
	succeeded="$(kc -n "${NAMESPACE}" get job "${JOB_NAME}" -o jsonpath='{.status.succeeded}' 2>/dev/null || true)"
	failed="$(kc -n "${NAMESPACE}" get job "${JOB_NAME}" -o jsonpath='{.status.failed}' 2>/dev/null || true)"
	if [ "${succeeded:-0}" -ge 1 ]; then
		outcome=succeeded
	elif [ "${failed:-0}" -ge 1 ]; then
		outcome=failed
	elif [ "$(date +%s)" -ge "${deadline}" ]; then
		outcome=timeout
	else
		sleep 5
	fi
done

logs() {
	kc -n "${NAMESPACE}" logs \
		-l "job-name=${JOB_NAME}" --all-containers --prefix "$@" 2>/dev/null || true
}

if [ "${outcome}" = succeeded ]; then
	logs --tail=-1 | grep -E 'pushing manifest for|containerimage\.digest' || true
	echo "build-cluster: job ${NAMESPACE}/${JOB_NAME} succeeded"
	exit 0
fi

echo "build-cluster: job ${NAMESPACE}/${JOB_NAME} ${outcome}; last log lines:" >&2
logs --tail=100 >&2
if [ "${outcome}" = timeout ]; then
	die "job ${NAMESPACE}/${JOB_NAME} did not finish within ${TIMEOUT}s (+120s grace)"
fi
die "job ${NAMESPACE}/${JOB_NAME} failed"
```

4. Create `hack/build-job.yaml` with EXACTLY the following content. Preserve every comment line, every indentation level, blank lines, and the single trailing newline. Do not reflow or "improve" anything, including the two inherited comments the reviewer note says to keep:

```yaml
# Parameterized BuildKit build Job.
#
# Rendered and applied by the release-to-image dispatcher when this repo is
# released, and by `hack/build-cluster.sh` when `make build` runs with a
# BUILD_TARGET other than `local`. The default local arm does not use it:
# `make build` with no BUILD_TARGET still builds with plain `docker build`.
#
# This file lives outside k8s/ on purpose: everything under k8s/ is deploy
# state reached through `make apply`, so a template kept there would be adopted
# as such.
#
# Template tokens:
#   __JOB_NAME__           Job name, derived from __TAG__ and sanitized for DNS
#   __REPO_URL__           git URL to clone
#   __REF__                git ref (branch, tag or commit) to build
#   __TAG__                image tag to push
#   __DOCKERFILE__         Dockerfile path inside the repository
#   __IMAGE__              target image repository, without tag
#   __PUSH__               "true" to push the built image
#   __PUSH_SECRET__        name of the dockerconfigjson secret to mount
#   __DEADLINE_SECONDS__   Job deadline in seconds
#   __SOURCE_DATE_EPOCH__  commit timestamp, decimal seconds
#
# Prerequisite (not created by this manifest): a kubernetes.io/dockerconfigjson
# secret in the build namespace, named by __PUSH_SECRET__, holding a credential
# that may push to the target registry.
apiVersion: batch/v1
kind: Job
metadata:
  name: __JOB_NAME__
  namespace: build
  labels:
    app.kubernetes.io/name: image-build
    app.kubernetes.io/component: build
    app.kubernetes.io/version: "__TAG__"
spec:
  backoffLimit: 0
  activeDeadlineSeconds: __DEADLINE_SECONDS__
  ttlSecondsAfterFinished: 86400
  template:
    metadata:
      labels:
        app.kubernetes.io/name: image-build
        app.kubernetes.io/component: build
        app.kubernetes.io/version: "__TAG__"
    spec:
      restartPolicy: Never
      automountServiceAccountToken: false
      initContainers:
        - name: clone
          image: alpine/git:v2.54.0@sha256:e8ceedc73bd80992ae8d58a7d24c58b8322146c354f1d2e81a97db4452068ec0
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              git init -q /src
              git -C /src remote add origin "$1"
              git -C /src fetch -q --depth=1 --tags origin "$2"
              git -C /src checkout -q --detach FETCH_HEAD
              git -C /src log -1 --format=%ct > /meta/source-date-epoch
              git -C /src log -1 --format=%cI > /meta/source-date-iso
              git -C /src rev-parse --short HEAD > /meta/git-commit
              git -C /src describe --tags --always --dirty > /meta/git-version
              echo "cloned $1 at $2: $(git -C /src rev-parse HEAD) epoch=$(cat /meta/source-date-epoch) version=$(cat /meta/git-version)"
            - clone
            - "__REPO_URL__"
            - "__REF__"
          env:
            - name: GIT_CONFIG_COUNT
              value: "1"
            - name: GIT_CONFIG_KEY_0
              value: safe.directory
            - name: GIT_CONFIG_VALUE_0
              value: /src
          # Memory requests are deliberately small: the build node runs at ~98%
          # of its request capacity, and a pod asking for a GiB of scheduling
          # headroom to do a few hundred MiB of work never schedules there.
          # The limits are the real constraint; a request is only a hint.
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: "1"
              memory: 1Gi
          # Hardened like any other container: the clone needs to write /src and
          # /meta and nothing else, so it keeps no capability and cannot escalate.
          securityContext:
            allowPrivilegeEscalation: false
            capabilities:
              drop: ["ALL"]
            seccompProfile:
              type: RuntimeDefault
          volumeMounts:
            - name: src
              mountPath: /src
            - name: meta
              mountPath: /meta
      containers:
        - name: build
          image: moby/buildkit:v0.34.1-rootless@sha256:f68752a5a94acfcdad2d07867b7075601a421638e17fc5f28efc1c814d0c4f89
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -eu
              cloned_epoch="$(cat /meta/source-date-epoch)"
              if [ "${cloned_epoch}" != "__SOURCE_DATE_EPOCH__" ]; then
                echo "REF __REF__ is commit epoch ${cloned_epoch} in the cluster but __SOURCE_DATE_EPOCH__ in the local repository; run git fetch and retry" >&2
                exit 1
              fi
              buildctl-daemonless.sh build \
                --frontend dockerfile.v0 \
                --local context=/src \
                --local dockerfile=/src \
                --opt filename=__DOCKERFILE__ \
                --opt platform=linux/amd64 \
                --opt build-arg:SOURCE_DATE_EPOCH=__SOURCE_DATE_EPOCH__ \
                --opt build-arg:BUILD_GIT_VERSION="$(cat /meta/git-version)" \
                --opt build-arg:BUILD_GIT_COMMIT="$(cat /meta/git-commit)" \
                --opt build-arg:BUILD_DATE="$(cat /meta/source-date-iso)" \
                --opt build-arg:DOCKER_REGISTRY=docker.io \
                --metadata-file /meta/metadata.json \
                --output type=image,name=__IMAGE__:__TAG__,push=__PUSH__,rewrite-timestamp=true
              cat /meta/metadata.json
          env:
            - name: BUILDKITD_FLAGS
              value: "--oci-worker-no-process-sandbox"
            - name: DOCKER_CONFIG
              value: "/docker-config"
          # Unconfined here is deliberate and is NOT an oversight left over from
          # the init containers above: rootless buildkitd with
          # --oci-worker-no-process-sandbox needs both profiles relaxed to run
          # nested containers. Tightening them breaks every build; the
          # unprivileged uid and the dropped capabilities are the boundary.
          securityContext:
            runAsUser: 1000
            runAsGroup: 1000
            seccompProfile:
              type: Unconfined
            appArmorProfile:
              type: Unconfined
          resources:
            requests:
              cpu: 500m
              memory: 256Mi
            limits:
              cpu: "2"
              memory: 4Gi
          volumeMounts:
            - name: src
              mountPath: /src
            - name: meta
              mountPath: /meta
            # Container-internal path, not a host path: rootless buildkitd writes its
            # state to $HOME/.local/share/buildkit inside the image, and needs it
            # writable. Not a self-containment violation.
            - name: buildkitd
              mountPath: /home/user/.local/share/buildkit
            - name: docker-config
              mountPath: /docker-config
              readOnly: true
      volumes:
        - name: src
          emptyDir: {}
        - name: meta
          emptyDir: {}
        - name: buildkitd
          emptyDir: {}
        - name: docker-config
          secret:
            secretName: __PUSH_SECRET__
            items:
              - key: .dockerconfigjson
                path: config.json
```

5. Create `hack/build-cluster-bootstrap.sh` with EXACTLY the following content. Preserve the shebang, every comment line, every tab, blank lines, and the single trailing newline:

```bash
#!/usr/bin/env bash
# Provisions the cluster-side prerequisites for a remote build: the `build`
# namespace and the docker.io push secret the Job mounts. Idempotent — running
# it twice exits 0 and leaves exactly one namespace and one secret.
#
# Called by hand before the first `make build BUILD_TARGET=<cluster>` against a
# cluster. It deliberately creates no Job: jobs are per-build, rendered by
# hack/build-cluster.sh, which refuses to run when one already exists.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE="${TEMPLATE:-${SCRIPT_DIR}/dockerconfig.json.tpl}"

BUILD_TARGET="${1:-}"
NAMESPACE="${NAMESPACE:-build}"
BUILD_PUSH_SECRET="${BUILD_PUSH_SECRET:-buildkit-push}"

die() {
	echo "build-cluster-bootstrap: $*" >&2
	exit 1
}

[ -n "${BUILD_TARGET}" ] || die "usage: $(basename "${BASH_SOURCE[0]}") <sun|nukedev|nukeprod|kubectl-context>"
[ -f "${TEMPLATE}" ] || die "template not found: ${TEMPLATE}"

# The same -teamvault-config value `make apply` takes (Makefile.k8s). Defaults to
# the config the repo's own .envrc uses, so an operator who has teamvault-cli set
# up does not have to export anything.
TEAMVAULT="${TEAMVAULT:-${HOME}/.config/teamvault-cli/config.json}"
[ -f "${TEAMVAULT}" ] || die "teamvault config not found: ${TEAMVAULT} (set TEAMVAULT to override)"
command -v teamvault-cli >/dev/null 2>&1 ||
	die "teamvault-cli not found on PATH; it resolves the lookup key in ${TEMPLATE}"

# Shared with hack/build-cluster.sh so the alias mapping cannot drift between
# provisioning and building.
source "${SCRIPT_DIR}/cluster-alias.sh"

# The rendered credential lives in a 600 temp file for the length of one
# `create secret --dry-run` and is removed on every exit path. It is never
# echoed, never logged, and never written into the repo.
RENDERED="$(mktemp)"
chmod 600 "${RENDERED}"
trap 'rm -f "${RENDERED}"' EXIT INT TERM

echo "build-cluster-bootstrap: cluster ${BUILD_TARGET} (kubectl context ${KUBE_CONTEXT})"

kc create namespace "${NAMESPACE}" --dry-run=client -o yaml | kc apply -f -
echo "build-cluster-bootstrap: namespace ${NAMESPACE} present"

# The lookup key comes from the template, so the template stays the single
# declaration of which TeamVault item and which registry this secret is for.
TEAMVAULT_KEY="$(sed -nE 's/.*"([A-Za-z0-9]{6,12})" \| teamvaultUser.*/\1/p' "${TEMPLATE}" | head -1)"
[ -n "${TEAMVAULT_KEY}" ] || die "no teamvaultUser lookup key found in ${TEMPLATE}"

# teamvault-cli, not teamvault-config-parser: the parser takes its password from
# the config file, which holds only url and user, so it authenticates unprivileged
# and gets 403 on this item. The CLI reads the login from the macOS Keychain.
TV_USER="$(teamvault-cli username --teamvault-config "${TEAMVAULT}" --teamvault-key="${TEAMVAULT_KEY}")"
TV_PASS="$(teamvault-cli password --teamvault-config "${TEAMVAULT}" --teamvault-key="${TEAMVAULT_KEY}")"
[ -n "${TV_USER}" ] && [ -n "${TV_PASS}" ] || die "teamvault returned an empty credential for key ${TEAMVAULT_KEY}"

# docker.io's canonical auths key, per the template.
printf '{"auths":{"https://index.docker.io/v1/":{"username":"%s","password":"%s"}}}' \
	"${TV_USER}" "${TV_PASS}" >"${RENDERED}"
unset TV_USER TV_PASS
[ -s "${RENDERED}" ] || die "failed to render ${TEMPLATE}"

kc create secret generic "${BUILD_PUSH_SECRET}" \
	-n "${NAMESPACE}" \
	--type=kubernetes.io/dockerconfigjson \
	--from-file=.dockerconfigjson="${RENDERED}" \
	--dry-run=client -o yaml | kc apply -f -
echo "build-cluster-bootstrap: secret ${NAMESPACE}/${BUILD_PUSH_SECRET} present"

echo "build-cluster-bootstrap: ready — make build BUILD_TARGET=${BUILD_TARGET}"
```

6. Create `hack/dockerconfig.json.tpl` with EXACTLY the following single line, followed by one trailing newline:

```json
{"auths":{"https://index.docker.io/v1/":{"username":"{{ "eqKWoq" | teamvaultUser }}","password":"{{ "eqKWoq" | teamvaultPassword }}"}}}
```

7. Make the three scripts executable. The YAML and template stay non-executable:
```
chmod +x hack/build-cluster.sh hack/cluster-alias.sh hack/build-cluster-bootstrap.sh
```

8. Replace `Makefile` so its final content is EXACTLY the following. The `precommit` and `test` targets come from the bootstrap commit and must stay byte-identical; do not add Docker calls to either. The local `build`/`upload`/`clean` recipes are unchanged; the cluster branch is new. Preserve tabs: every recipe line starts with a real tab character.

```makefile
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
```

9. In `CHANGELOG.md`, ensure an `## Unreleased` section is the FIRST `## ` heading in the file, with at least one bullet naming `BUILD_TARGET`. If the section is absent, insert it immediately before the first existing `## ` heading (for example `## 1.3.1`). If the section is already present, leave it in place and make sure the `BUILD_TARGET` bullet exists. Use exactly this block:

```markdown
## Unreleased

- feat: add `BUILD_TARGET` selector to `make build` — `local` (default) keeps plain `docker build`; a cluster target renders `hack/build-job.yaml`, applies it, and waits for the Job
- feat: add `hack/build-job.yaml`, `hack/build-cluster-bootstrap.sh` and `hack/dockerconfig.json.tpl` alongside `hack/build-cluster.sh` and `hack/cluster-alias.sh`
- feat: `make upload` and `make clean` are no-ops for a cluster target
```

10. Do not create a `k8s/` directory and do not move `hack/build-job.yaml` under one. Do not modify any file other than the five `hack/` files, `Makefile`, and `CHANGELOG.md`.
</requirements>

<constraints>
- The local recipe's `docker build` arguments must not change: `--no-cache --rm=true --platform=linux/amd64 -t $(REGISTRY)/$(IMAGE):$(VERSION) .` stays, and no build args are added.
- `VERSION`, `REGISTRY` and `IMAGE` keep their current definitions and meanings. `VERSION` remains the image tag and keeps its `?= 1.3.0` default on the first line.
- The defaulted-`VERSION` guard must sit inside the cluster branch only. `VERSION` is assigned in the file itself, so `$(origin VERSION)` reads `file` on every bare `make build`; a parse-time guard would refuse the local arm. Do NOT carry over the upstream `ALLOW_DEFAULT_VERSION` bypass: the refusal is unconditional.
- `hack/build-job.yaml` must not live under a `k8s/` directory. This repository has no `k8s/` directory and must not gain one for this file.
- The Job image is referenced by digest, not by a floating tag (keep the pinned digests in the YAML).
- No new runtime dependency in the built image. This change is build tooling only.
- The local path must work with no kubeconfig and no cluster credentials present.
- `make precommit` and `make test` must stay Docker-free: the container has no daemon. `make test` is intentionally a no-op, not a test suite.
- The five `hack/` files are copied byte-faithfully with their comments and hardening intact. Repository-specific values come from the Makefile environment, not from edits to the scripts. The inherited `Makefile.docker` comment in `build-cluster.sh` and the "release-to-image dispatcher" comment in `build-job.yaml` are accepted as-is; do not edit them.
- Do not "correct" the two deliberate divergences from `bborbe/go-skeleton`'s `docs/build-migration-guide.md`: the local arm stays plain `docker build`, and `VERSION` keeps `?= 1.3.0`.
- This repository ships a `Dockerfile` and shell build tooling, not Go code. Do not cite or follow language-specific plugin documentation.
- Do NOT commit — dark-factory handles git.
- Do not run `docker`, `kubectl`, `git`, or the scripts themselves. Only static checks are available in this container.
</constraints>

<verification>
Run each command from the repository root. All must succeed. These are the container-executable checks; cluster behaviour is verified by the operator rung after merge.

- `test -f hack/build-cluster.sh -a -f hack/cluster-alias.sh -a -f hack/build-job.yaml -a -f hack/build-cluster-bootstrap.sh -a -f hack/dockerconfig.json.tpl`
- `bash -n hack/build-cluster.sh && bash -n hack/cluster-alias.sh && bash -n hack/build-cluster-bootstrap.sh`
- `test -x hack/build-cluster.sh && test -x hack/cluster-alias.sh && test -x hack/build-cluster-bootstrap.sh`
- `test "$(grep -c 'contains a newline' hack/build-cluster.sh)" -ge 1`
- `test "$(grep -c 'rendered_namespace' hack/build-cluster.sh)" -ge 1`
- `test "$(grep -c 'automountServiceAccountToken: false' hack/build-job.yaml)" -ge 1`
- `test "$(grep -c 'safe.directory' hack/build-job.yaml)" -ge 1`
- `test "$(grep -c 'oci-worker-no-process-sandbox' hack/build-job.yaml)" -ge 1`
- `test "$(grep -c '^BUILD_TARGET' Makefile)" -ge 1`
- `test "$(grep -cE '^[[:space:]]*hack/build-cluster\.sh' Makefile)" -ge 1`
- `make -n build | grep -qx 'docker build --no-cache --rm=true --platform=linux/amd64 -t docker.io/bborbe/openldap:1.3.0 .'`
- `! make -n build | grep -q 'hack/build-cluster.sh'`
- `make -n build BUILD_TARGET=nukeprod REF=deadbeef VERSION=scratch-tag | grep -q "IMAGE='docker.io/bborbe/openldap'"`
- `make -n build BUILD_TARGET=nukeprod REF=deadbeef VERSION=scratch-tag | grep -q "DOCKER_REGISTRY='docker.io'"`
- `make -n build BUILD_TARGET=nukeprod REF=deadbeef VERSION=scratch-tag | grep -q 'hack/build-cluster.sh'`
- `make -n build BUILD_TARGET=nukeprod REF=deadbeef 2>&1 | grep -q 'the cluster arm needs an explicit VERSION'`
- `make upload BUILD_TARGET=nukeprod VERSION=scratch-tag | grep -q 'nothing to do'`
- `make clean BUILD_TARGET=nukeprod | grep -q 'nothing to do'`
- `test "$(awk '/^## /{print; exit}' CHANGELOG.md)" = '## Unreleased'`
- `grep -A6 '^## Unreleased' CHANGELOG.md | grep -q 'BUILD_TARGET'`
- `make precommit` — must exit 0.
- `make test` — must exit 0.

Host-side and cluster-side checks are intentionally not run here; they belong to the spec's operator-executable rung after merge and cannot run in this container (no daemon, no cluster credentials, masked `.git`).
</verification>
