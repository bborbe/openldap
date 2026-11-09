# Definition of Done

A prompt is complete when ALL of the following are true:

## Build

- [ ] `make build` succeeds (docker image builds for linux/amd64)
- [ ] No new build warnings

## Content

- [ ] Follows the existing layout under `files/`
- [ ] No secrets or credentials committed

## Style

- [ ] No absolute paths — paths relative to the image working directory
