---
status: approved
approved: "2026-11-09T08:43:23Z"
branch: dark-factory/cluster-build-arm
---

## Summary

- `make build` gains a `BUILD_TARGET` selector. `local` — the default — keeps today's plain `docker build` invocation and its `$(VERSION)` tag. Naming a cluster instead renders a Kubernetes Job, applies it to that cluster's `build` namespace, waits for it, and reports the result.
- The Job clones the requested git ref, builds `linux/amd64` with rootless BuildKit, and pushes `docker.io/bborbe/openldap:<TAG>` using a credential mounted inside the pod.
- Five files land under `hack/`, copied verbatim from pinned source refs: `build-cluster.sh`, `cluster-alias.sh` and `build-job.yaml` from `bborbe/agent-task-executor@91a7e64e160f30be8af0aea64635e1e11bc86731` (v0.57.4); `build-cluster-bootstrap.sh` and `dockerconfig.json.tpl` from `bborbe/go-skeleton@eb050aa20bb6194d8af7e47baf8880df789bd1ca` (3 commits after v0.8.3). The YOLO container mounts only this repository and `.dark-factory.yaml` declares no `extraMounts`, so the prompt must carry the file bodies inline rather than reach a sibling repo.
- `upload` and `clean` become no-ops for a cluster target — the cluster arm already pushed, and nothing was built on the invoking host.
- The local arm's observable behaviour is unchanged: same `docker build` arguments, same `docker.io/bborbe/openldap:1.3.0` tag, image present in the local Docker store.

## Problem

Every `bborbe` image build today runs `docker build` on whichever machine invokes `make build`. This repository's `Makefile` has a single `build` target with no selector, so its image can be produced on one Mac and nowhere else. That serialises the release on a machine that may be asleep or have its Docker daemon stopped, and it is why `openldap` sits in the un-migrated half of the build-cluster rollout.

The deployment already depends on this image being reproducible elsewhere: `nuke/teamvault/k8s/ldap-sts.yaml:21,40` renders `${REGISTRY_HOST}/bborbe/openldap:1.3.0`, and that name is populated by nuke's mirror step from the `docker.io` image this build produces.

## Goal

`make build` with no `BUILD_TARGET` behaves exactly as it does today. `make build BUILD_TARGET=<cluster> REF=<git-ref> VERSION=<tag>` creates a Job in that cluster which clones the ref, builds and pushes the image; the make target blocks until the Job reaches a terminal state and exits non-zero if it failed. The Job spec is one reusable, parameterized file at `hack/build-job.yaml` that nothing else in the repo adopts as deploy state.

## Non-goals

- Migrating any other repository. This is `openldap` only.
- Changing image naming, the `docker.io/bborbe/openldap` repository, or the local arm's `$(VERSION)` tag and its `1.3.0` default.
- Loading the built image back to the invoking machine (`--load`). Rejected, not deferred: it keeps the push credential on the local machine.
- Pushing to the in-cluster registries, and the nuke mirror pin bump in `nuke/base/Makefile:23`. The mirror stays a mirror.
- Multi-arch images. `linux/amd64` only, matching the cluster nodes.
- Provisioning cluster namespaces or credentials as a deliverable. `hack/build-cluster-bootstrap.sh` runs them, once, as a prerequisite.
- Release-time build triggering. That is a separate concern.
- A buildx Kubernetes driver path, a Kaniko path, or any second executor. One executor ships.
- Adding `BUILD_*` build args to the `Dockerfile`. It consumes none today and needs none.
- An `ALLOW_DEFAULT_VERSION` escape hatch. `agent-task-executor` ships one as a bypass of the defaulted-`VERSION` guard; this repo takes the guard without the bypass, so the refusal is unconditional.

## Assumptions

- The cluster aliases are `sun`, `nukedev` and `nukeprod`; `hack/cluster-alias.sh` maps them to `~/.kube/sun` (context `default`), `~/.kube/nuke-dev` (context `nuke-dev`) and `~/.kube/nuke-prod` (context `nuke-prod`). Any other value is treated as a plain kubectl context in the ambient kubeconfig.
- The `build` namespace and the `buildkit-push` secret are provisioned once by `hack/build-cluster-bootstrap.sh <cluster>`; this spec does not create them and the Job cannot push without them.
- `crane`, `teamvault-cli` (with a Keychain login for the docker.io push account) and a `kubectl` wrapper for the target cluster are present on the operator's host.
- The target cluster can reach `github.com` and `docker.io`.
- The operator runs the cluster-arm evidence commands against the same cluster the Job was created in, named by the wrapper matching `BUILD_TARGET`.
- The scratch tag passed as `VERSION` is lowercase and DNS-safe, so the derived Job name equals `build-<scratch-tag>`.

## Acceptance Criteria

- [ ] **`BUILD_TARGET` defaults to `local` and the local recipe is unchanged** — evidence: `make -n build` with no `BUILD_TARGET` emits `docker build --no-cache --rm=true --platform=linux/amd64 -t docker.io/bborbe/openldap:1.3.0 .` as its only command line, and its output contains no occurrence of `hack/build-cluster.sh`.
- [ ] **The local arm still produces an image in the local Docker store** — evidence: after `docker rmi docker.io/bborbe/openldap:1.3.0`, `make build` exits 0 and `docker image inspect -f '{{.Id}}' docker.io/bborbe/openldap:1.3.0` exits 0 printing a non-empty `sha256:` id.
- [ ] **The cluster arm refuses a defaulted `VERSION`** — evidence: `make build BUILD_TARGET=<cluster> REF=<full-sha>` (no `VERSION` on the command line) exits non-zero, its stderr contains `the cluster arm needs an explicit VERSION`, and `kubectl<wrapper> -n build get jobs -o name | wc -l` is the same before and after the attempt.
- [ ] **Post-Deploy (Rung-3):** a cluster target creates a Job that completes and pushes — evidence: `make build BUILD_TARGET=<cluster> REF=<full-sha> VERSION=<scratch-tag>` exits 0; `kubectl<wrapper> -n build get job build-<scratch-tag> -o jsonpath='{.status.succeeded}'` returns `1`; `kubectl<wrapper> -n build get pod -l job-name=build-<scratch-tag> -o jsonpath='{.items[0].spec.nodeName}'` returns a non-empty node name; `crane digest docker.io/bborbe/openldap:<scratch-tag>` returns a `sha256:` digest.
  - `deploy_check:` `kubectlsun -n build get namespace build -o jsonpath='{.metadata.name}'`
  - `deploy_target:` `build`

  This check asserts the `build` namespace exists, not deployment freshness — the change ships build tooling and deploys nothing, so a pass here means the target namespace is present, never that a new build was deployed.
- [ ] **The pushed reference is the repository the deployment consumes** — evidence: the `make -n build BUILD_TARGET=<cluster> REF=<full-sha> VERSION=<scratch-tag>` output contains `IMAGE='docker.io/bborbe/openldap'` and `DOCKER_REGISTRY='docker.io'`, and the digest recorded in the previous criterion resolves at exactly `docker.io/bborbe/openldap:<scratch-tag>`.
- [ ] **The cluster-built image is absent from the invoking machine** — evidence: `docker image inspect docker.io/bborbe/openldap:<scratch-tag>` fails with `No such image`.
- [ ] **All five `hack/` files are present, parse, and carry the copied hardening** — evidence: `test -f` succeeds for `hack/build-cluster.sh`, `hack/cluster-alias.sh`, `hack/build-job.yaml`, `hack/build-cluster-bootstrap.sh` and `hack/dockerconfig.json.tpl`; `bash -n` exits 0 for each of the three scripts; `grep -c 'contains a newline' hack/build-cluster.sh` returns ≥ 1; `grep -c 'rendered_namespace' hack/build-cluster.sh` returns ≥ 1; `grep -c 'automountServiceAccountToken: false' hack/build-job.yaml` returns ≥ 1; `grep -c 'safe.directory' hack/build-job.yaml` returns ≥ 1; `grep -c 'oci-worker-no-process-sandbox' hack/build-job.yaml` returns ≥ 1.
- [ ] **`upload` and `clean` are no-ops for a cluster target** — evidence: `make upload BUILD_TARGET=<cluster> VERSION=<scratch-tag>` exits 0 and its output contains `nothing to do`; `make clean BUILD_TARGET=<cluster>` exits 0 and its output contains `nothing to do`.
- [ ] **`CHANGELOG.md` carries an `## Unreleased` section naming the change** — evidence: `awk '/^## /{print; exit}' CHANGELOG.md` prints `## Unreleased`, and `grep -A6 '^## Unreleased' CHANGELOG.md | grep -c 'BUILD_TARGET'` returns ≥ 1.
- [ ] **`make precommit` and `make test` exist and run without a Docker daemon** — evidence: `make precommit` exits 0 and `make test` exits 0 on a host where `docker` is absent or the daemon is stopped, and neither target's output contains `docker build`.

## Verification

### Container-executable (runs inside the YOLO container at prompt time)

- `make -n build` — prints the unchanged `docker build` line and no `hack/build-cluster.sh`
- `make -n build BUILD_TARGET=nukeprod REF=<sha> VERSION=<scratch-tag>` — prints the `hack/build-cluster.sh` invocation with `IMAGE='docker.io/bborbe/openldap'`
- `bash -n hack/build-cluster.sh hack/cluster-alias.sh hack/build-cluster-bootstrap.sh` — exits 0
- `test -f hack/build-cluster.sh -a -f hack/cluster-alias.sh -a -f hack/build-job.yaml -a -f hack/build-cluster-bootstrap.sh -a -f hack/dockerconfig.json.tpl` — exits 0
- `grep -c 'contains a newline' hack/build-cluster.sh` — returns ≥ 1
- `grep -c 'rendered_namespace' hack/build-cluster.sh` — returns ≥ 1
- `grep -c 'automountServiceAccountToken: false' hack/build-job.yaml` — returns ≥ 1
- `grep -c 'safe.directory' hack/build-job.yaml` — returns ≥ 1
- `grep -c '^BUILD_TARGET' Makefile` — returns ≥ 1
- `grep -cE '^[[:space:]]*hack/build-cluster\.sh' Makefile` — returns ≥ 1
- `awk '/^## /{print; exit}' CHANGELOG.md` — prints `## Unreleased`
- `make precommit` — exits 0 with no Docker daemon present
- `make test` — exits 0 with no Docker daemon present

### Operator-executable (runs on the host after PR merge)

`kubectl<wrapper>` means `kubectlsun` for `sun`, `kubectlnukedev` for `nukedev`, `kubectlnukeprod` for `nukeprod` — the wrapper pins the kubeconfig and context, and `--context` / `--kubeconfig` are refused by the operator's shim.

- `make build && docker image inspect -f '{{.Id}}' docker.io/bborbe/openldap:1.3.0` — the local arm still lands an image
- `make build BUILD_TARGET=<cluster> REF=<full-sha>` — refuses, naming the missing explicit `VERSION`
- `make build BUILD_TARGET=<cluster> REF=<full-sha> VERSION=<scratch-tag>` — a cluster Job runs to completion
- `kubectl<wrapper> -n build get job build-<scratch-tag> -o jsonpath='{.status.succeeded}'` — returns `1` (the Job carries `ttlSecondsAfterFinished: 86400`, so this resolves within 24 h of completion)
- `kubectl<wrapper> -n build get pod -l job-name=build-<scratch-tag> -o jsonpath='{.items[0].spec.nodeName}'` — returns a node name
- `crane digest docker.io/bborbe/openldap:<scratch-tag>` — returns the digest the Job pushed
- `docker image inspect docker.io/bborbe/openldap:<scratch-tag>` — fails with `No such image`

**No scenario is added.** The operator rung above is the accepted end-to-end substitute: it runs the real cluster Job, reads its terminal state and node, resolves the pushed digest through `crane`, and asserts the image is absent locally — the four observations a no-op cannot fake. This repository has no scenario harness, and bootstrapping one to replay a proof the operator rung already performs is disproportionate.

## Desired Behavior

1. `make build` with no `BUILD_TARGET`, or `BUILD_TARGET=local`, runs the existing `docker build` recipe and leaves the image in the local Docker store under `docker.io/bborbe/openldap:$(VERSION)`.
2. `make build BUILD_TARGET=<cluster>` renders `hack/build-job.yaml` with the run's values, applies it to the cluster's `build` namespace, and blocks until the Job reaches a terminal state.
3. The make target exits 0 when the Job succeeded and non-zero when it failed, printing the Job's pod log tail on failure so the cause is visible without a separate `kubectl` call.
4. The cluster arm refuses a `VERSION` that came from the Makefile default (`$(origin VERSION)` = `file`), naming the missing explicit tag, and creates no Job.
5. The Job's git init container clones the requested `REF` — not the default branch — into an `emptyDir`, and derives `SOURCE_DATE_EPOCH` from that commit. A ref that does not resolve in the local repository aborts the run before a Job is created.
6. The build container runs `buildctl-daemonless.sh build` with `--opt build-arg:SOURCE_DATE_EPOCH=<epoch>`, the `BUILD_GIT_VERSION` / `BUILD_GIT_COMMIT` / `BUILD_DATE` / `DOCKER_REGISTRY` build args, and `--output type=image,name=<IMAGE>:<TAG>,push=true,rewrite-timestamp=true`. This Dockerfile consumes none of those build args; they are passed and ignored.
7. The push credential is read from a mounted secret whose `items:` remap presents it as `config.json` under `DOCKER_CONFIG`.
8. `BUILD_TARGET=local` never touches a cluster: no Job is created, no kubeconfig is required, and the target works on a machine with no cluster credentials.
9. The Job is named `build-<TAG>`, lowercased and sanitised to a DNS-1123 name, so a run can be located by the tag it produced.
10. `upload` and `clean` print `nothing to do` and exit 0 when `BUILD_TARGET` is not `local` — otherwise a cluster build followed by `make clean` would `docker rmi` the unrelated local `1.3.0` image.
11. `make precommit` and `make test` exist and are container-safe: `precommit` runs `bash -n` over the three `hack/` scripts and `make -n build`, and neither target invokes `docker`. Both land in a bootstrap commit before any prompt runs — the pipeline's preflight executes `make precommit` before the prompt container starts, so a prompt that creates them is too late.

## Constraints

- The local recipe's `docker build` arguments must not change: `--no-cache --rm=true --platform=linux/amd64 -t $(REGISTRY)/$(IMAGE):$(VERSION) .` stays, and no build args are added.
- `VERSION`, `REGISTRY` and `IMAGE` keep their current definitions and meanings. `VERSION` remains the image tag and keeps its `?= 1.3.0` default on line 1.
- **The defaulted-`VERSION` guard must sit inside the cluster branch only.** `VERSION` is assigned in the file itself, so `$(origin VERSION)` reads `file` on every bare `make build`; a guard evaluated at parse time would refuse the local arm, which is the opposite of the intent. The copied `ALLOW_DEFAULT_VERSION` bypass is deliberately not carried over (see Non-goals).
- `hack/build-job.yaml` must not live under a `k8s/` directory — a directory-scanned `make apply` would adopt it as deploy state. This repository has no `k8s/` directory today and must not gain one for this file.
- The Job image is referenced by digest, not by a floating tag.
- No new runtime dependency in the built image. This change is build tooling only.
- The local path must work with no kubeconfig and no cluster credentials present.
- `docs/dod.md`'s "`make build` succeeds" is a host-side check: the dark-factory container has no Docker daemon, so a prompt must not treat its inability to run `docker build` as a failure. `make -n build` and the `bash -n` checks are the container-executable substitutes.
- **`make precommit` and `make test` are the pipeline's gates and both land in a bootstrap commit before any prompt runs.** `.dark-factory.yaml` leaves `validationCommand: make precommit` and `testCommand: make test` at their dark-factory defaults, and preflight executes `make precommit` *before* the prompt container starts. Both targets are therefore added up front and must stay Docker-free, since the container has no daemon.
- **No Go-specific plugin documentation.** This repo ships a `Dockerfile` and build scripts, not Go code. Prompts must not cite `coding/docs/go-makefile-commands.md` or any other language-specific plugin doc, and `make test` is intentionally a no-op rather than a test suite.
- The five `hack/` files are copied from the pinned refs with their comments and hardening intact; the repository-specific values (image, repo URL) come from the Makefile environment, not from edits to the scripts. One inherited comment in `build-job.yaml` refers to a release-to-image dispatcher this repo does not have — that inaccuracy is accepted rather than edited, to keep the copy byte-faithful.
- **One deliberate divergence from the pins, recorded 2026-11-09 after the PR review.** `build-cluster-bootstrap.sh` rendered the TeamVault credential into `dockerconfig.json` with a bare `printf '%s'`, so a password containing `"` or `\` produced malformed JSON — rejected at secret creation, or accepted and then failing at push with a 401 that names nothing. It now escapes both characters (backslash first, then quote) before interpolating, and rejects a credential carrying any control byte rather than trying to `\u00XX`-escape it — a control character in a registry credential is a bug in what TeamVault returned, and failing loudly at bootstrap beats a 401 at push. This is the only edit to any of the five copies; the other four remain byte-identical to `agent-task-executor@91a7e64` and `go-skeleton@eb050aa`, and the fix should be carried upstream to `go-skeleton` rather than diverging further here.
- **Reference**: the canonical procedure is `bborbe/go-skeleton` `docs/build-migration-guide.md` at `eb050aa20bb6194d8af7e47baf8880df789bd1ca`. This repo deliberately diverges in two places — the local arm stays plain `docker build` (the guide mandates `buildx` with `rewrite-timestamp`), and `VERSION` keeps `?= 1.3.0` (the guide has no default). A prompt must not "correct" either divergence.

## Failure Modes

| Trigger | Expected behavior | Recovery |
|---|---|---|
| `BUILD_TARGET` names a cluster alias with no kubeconfig file | `build-cluster.sh` exits non-zero naming the missing file; no Job is created | Provision the kubeconfig, or use `sun` / `nukedev` / `nukeprod` |
| `BUILD_TARGET` names an unknown target | `build-cluster.sh` dies at its context check with `unknown BUILD_TARGET '<x>'; accepted values: sun nukedev nukeprod <contexts>`; no cluster call is made and no Job is created | Rerun with `sun`, `nukedev` or `nukeprod` |
| The cluster is unreachable | `build-cluster.sh` exits non-zero at the existence probe, carrying kubectl's connection error; no partial Job is left | Rerun when the cluster is available; `kubectl<wrapper> get ns build` confirms it |
| The Job is rejected at admission (pod-security, RBAC) | The make target prints the Job's events and exits non-zero | `kubectl<wrapper> -n build describe job build-<TAG>` shows no `FailedCreate` after the fix |
| The `build` namespace or `buildkit-push` secret is missing | The Job is created but its pod cannot mount the secret and never starts | Run `hack/build-cluster-bootstrap.sh <cluster>` once, then rerun the build |
| The git clone fails in the init container | The Job fails; its log names the ref and the git error | Correct `REF`, or verify the ref exists on the remote |
| The cluster resolves `REF` to a different commit than the local repository | The build container refuses before building: `REF <ref> is commit epoch <x> in the cluster but <y> in the local repository` | Run `git fetch` locally and rerun |
| The registry throttles the push | The Job fails at the push with a `429` in its log | Wait and rerun; the Job is idempotent per tag |
| The registry push is refused | The Job fails at the push; its log carries the registry error | Verify the mounted secret and its `items:` remap, then rerun |
| A Job with the same name already exists | `build-cluster.sh` refuses before applying and names the delete command | Delete the old Job, or use a different `VERSION` |
| The Job exceeds its deadline | The make target fails and names the deadline it waited | Raise `BUILD_TIMEOUT`, or investigate why the build stalled |
| The build node cannot schedule the pod (request capacity) | The pod stays `Pending` and the Job hits its deadline; the make target exits non-zero | `kubectl<wrapper> -n build describe pod -l job-name=build-<TAG>` shows the scheduling event; free capacity or lower the request |
| `make build` is interrupted mid-wait | The Job continues in the cluster; a later `kubectl<wrapper> get job build-<TAG>` reports its state | Read the Job's state, or delete it explicitly |

## Security / Abuse

- The push credential exists only as a cluster secret, mounted into the build pod. It is never written to the invoking machine, never passed as a make variable, and never printed.
- `hack/build-cluster.sh` whitelists every value it substitutes into the manifest and rejects embedded newlines before rendering, so a crafted `REF`, `TAG` or `IMAGE` cannot inject YAML or shell.
- The `items:` remap is load-bearing: without it the secret file keeps its own name while Docker looks for `config.json`, and auth fails in the same shape a missing credential produces.
- `buildctl-daemonless.sh` runs rootless with `--oci-worker-no-process-sandbox`. No privileged pod, no host namespace, no Docker socket.
- The init container sets `automountServiceAccountToken: false` and drops all capabilities; the build container carries no cluster credentials and cannot create, read or modify other resources.
- `REF` is passed as a clone argument, not interpolated into a shell string, so a crafted ref cannot execute commands in the init container.

## Suggested Decomposition

**One prompt, deliberately.** The whole change is five static files copied verbatim plus one Makefile branch; splitting it produced four prompts whose commits were each discarded by dark-factory's post-execution `FetchBranch` step under `workflow: worktree` (see `# Progress` on the task). A single prompt has no second fetch to fail on.

| # | Prompt focus | Covers DBs | Covers ACs | Depends on |
|---|---|---|---|---|
| 1 | Copy the five `hack/` files verbatim from the pinned refs, add the `BUILD_TARGET` selector + cluster branch + defaulted-`VERSION` guard to the Makefile, make `upload`/`clean` no-ops for a cluster target, and add the `## Unreleased` entry | 1–10 | 1–9 | — |

**How the prompt obtains the bodies.** The prompt-creator runs on the host, not in the container. It reads each file at generation time with `git -C ~/Documents/workspaces/agent-task-executor show 91a7e64e160f30be8af0aea64635e1e11bc86731:hack/<file>` (and `git -C ~/Documents/workspaces/go-skeleton show eb050aa20bb6194d8af7e47baf8880df789bd1ca:hack/<file>` for `build-cluster-bootstrap.sh` and `dockerconfig.json.tpl`) and inlines the content into the prompt body. The executing container must never be asked to reach either repository. If generation is ever containerised, the fallback is to land the five bodies under `docs/` in this repo first and have the prompt copy from there.

**DB11 / AC10 (`precommit`, `test`) are already satisfied by a bootstrap commit** — the pipeline's preflight runs `make precommit` before any prompt container starts, so they cannot be created by a prompt. The operator-executable rung runs after merge, so no prompt depends on a cluster being reachable.

## Do-Nothing Option

`openldap`'s image keeps requiring this Mac. The repo stays in the un-migrated half of the build-cluster rollout, the goal's per-repo evidence row cannot be written, and the release path keeps its single point of failure. The mirror and the StatefulSet keep pulling an image that can only be cut by hand on one machine.
