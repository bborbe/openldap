---
status: completed
spec: [001-cluster-build-arm]
summary: 'Added executable hack/cluster-alias.sh and hack/build-cluster.sh verbatim from the pinned upstream revision and recorded the change under ## Unreleased in CHANGELOG.md.'
execution_id: f3195b02-391b-5a9e-91c1-3f957ee9a6ad-exec-001-copy-cluster-scripts
dark-factory-version: dev
created: "2026-11-09T10:00:00Z"
queued: "2026-11-09T10:03:50Z"
started: "2026-11-09T10:03:51Z"
completed: "2026-11-09T10:04:34Z"
branch: dark-factory/cluster-build-arm
---

<!-- REVIEWER NOTE (not an instruction to the agent): the spec does not state
     file modes. The Makefile invokes `hack/build-cluster.sh` directly, so it
     must be executable; `chmod +x` is included for that reason. File CONTENT
     must remain byte-for-byte identical to the bodies below. -->

<summary>
- Introduces two helper scripts used by the cluster build path.
- One maps friendly cluster names to the kubeconfig and context kubectl needs.
- One renders the parameterized build Job and drives it to a terminal state.
- Both are reproduced exactly from a pinned upstream revision.
- The scripts are not invoked by make yet; this prompt only lands them.
- No Docker, Makefile, or image behavior changes here.
</summary>

<objective>
Land `hack/cluster-alias.sh` and `hack/build-cluster.sh` verbatim from the pinned upstream revision so a later prompt can wire them into `make build`. Nothing invokes them yet.
</objective>

<context>
Read these repository files before starting:
- `Makefile` — current `build`, `upload`, `clean`, `precommit`, `test` targets.
- `.dark-factory.yaml` — workflow is `worktree`, so the `.git` directory is masked inside the container.
- `docs/dod.md` — definition of done.

This repository ships a `Dockerfile` and shell build tooling; it contains no Go code. Do NOT consult language-specific plugin documentation. The `hack/` directory does not exist yet.

The two files below come from `bborbe/agent-task-executor@91a7e64e160f30be8af0aea64635e1e11bc86731` (v0.57.4). The executing container has no network path to that repository, so the full bodies are inlined here and must be written exactly as shown.
</context>

<requirements>
1. Create the `hack/` directory if it does not exist.

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

4. Make both scripts executable: `chmod +x hack/build-cluster.sh hack/cluster-alias.sh`.

5. Do not modify any other file. Do not add a `k8s/` directory.
</requirements>

<constraints>
- The two files are copied byte-faithfully; comments and hardening must remain intact.
- `hack/build-job.yaml` must not live under a `k8s/` directory; do not create one.
- This change adds no runtime dependency to the built image.
- Do NOT commit — dark-factory handles git.
- Existing targets (`make precommit`, `make test`) must still pass and must stay Docker-free.
- Do not run `docker`, `kubectl`, or the scripts themselves; only static checks are available in this container.
</constraints>

<verification>
Run each command from the repository root. All must succeed.

- `test -f hack/build-cluster.sh && test -f hack/cluster-alias.sh`
- `for f in hack/*.sh; do bash -n "$f" || exit 1; done`
- `test -x hack/build-cluster.sh && test -x hack/cluster-alias.sh`
- `test "$(grep -c 'contains a newline' hack/build-cluster.sh)" -ge 1`
- `test "$(grep -c 'rendered_namespace' hack/build-cluster.sh)" -ge 1`
- `make precommit` — must exit 0.
</verification>
