# Changelog

All notable changes to this project will be documented in this file.

Please choose versions by [Semantic Versioning](http://semver.org/).

* MAJOR version when you make incompatible API changes,
* MINOR version when you add functionality in a backwards-compatible manner, and
* PATCH version when you make backwards-compatible bug fixes.

## Unreleased

- feat: add `BUILD_TARGET` selector to `make build` — `local` (default) keeps plain `docker build`; a cluster target renders `hack/build-job.yaml`, applies it, and waits for the Job
- feat: add `hack/build-job.yaml`, `hack/build-cluster-bootstrap.sh` and `hack/dockerconfig.json.tpl` alongside `hack/build-cluster.sh` and `hack/cluster-alias.sh`
- feat: `make upload` and `make clean` are no-ops for a cluster target

## 1.3.1

- chore(dark-factory): worktree workflow with PR delivery

## 1.3.0

- Copy DB_CONFIG 
- remove docker build-args

## 1.2.0

- Update alpine to 3.9

## 1.1.0

- Initial Version
