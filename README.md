# Deploy to Anyport

Deploy a container image to an [Anyport](https://anyport.dev) app from GitHub Actions, and fail
the job if the rollout does.

Your workflow builds and pushes the image the way it already does. This action tells Anyport to
run it: it writes the new image to the app, publishes it, and waits until the cluster reports
the new version healthy.

## Usage

```yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - uses: actions/checkout@v4

      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - uses: docker/build-push-action@v6
        with:
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ github.sha }}

      - uses: anyport-labs/deploy-action@v1
        with:
          token: ${{ secrets.ANYPORT_TOKEN }}
          project: shop
          app: api
          image: ghcr.io/${{ github.repository }}:${{ github.sha }}
```

Deploy an immutable tag such as the commit SHA rather than `latest`, so every deploy is a
distinct revision you can roll back to.

### Link the deployment to a GitHub environment

```yaml
    environment:
      name: production
      url: ${{ steps.deploy.outputs.url }}
    steps:
      - id: deploy
        uses: anyport-labs/deploy-action@v1
        with:
          token: ${{ secrets.ANYPORT_TOKEN }}
          project: shop
          app: api
          image: ghcr.io/acme/api:${{ github.sha }}
```

## Create a token

The action signs in with a service token, never a person's login:

```bash
anyport token create github-actions --role developer --expires-in 90
```

The secret is printed once. Save it as a repository or environment secret named
`ANYPORT_TOKEN`. A `developer` token can deploy; it does not need `admin`. To limit it to one
cluster or project, make it an organization `viewer` and grant it `developer` where it deploys:

```bash
anyport access grant staging github-actions --role developer
```

Every deploy shows up in the Anyport audit log under the token's name, and
`anyport token revoke github-actions` ends it.

## Inputs

| Input | Required | Default | |
|---|---|---|---|
| `token` | yes | | Service token (`apt_…`). Pass it from a secret. |
| `project` | yes | | Project the app belongs to. |
| `app` | yes | | App to deploy. |
| `image` | yes | | Image to deploy. The cluster must be able to pull it; for a private registry, give the app a registry secret. |
| `cluster` | no | | Cluster to find the project on, when the same project name exists on more than one. |
| `wait` | no | `true` | Wait for the rollout, and fail the step if it fails. |
| `wait-timeout` | no | `5m` | How long to wait, e.g. `90s`, `10m`. |
| `publish` | no | `true` | `false` saves the change as a draft to review and publish from the console. |
| `cli-version` | no | `latest` | [`anyport` CLI release](https://github.com/anyport-labs/anyport-helm/releases) to use, e.g. `v0.0.15`. Pin it for repeatable builds. |
| `endpoint` | no | | API endpoint of a self-hosted Anyport console. |

## Outputs

| Output | |
|---|---|
| `url` | The app's first public URL, or empty if it has none. |
| `cli-version` | The `anyport` CLI version the deploy ran with. |

## What it does

1. Downloads the `anyport` CLI from its public release, checks it against the release's
   checksums, and adds it to `PATH`. Later steps in the job can run `anyport` too.
2. Runs `anyport app deploy <app> --image <image> --project <project> --wait`, with the token in
   `ANYPORT_TOKEN`.

If someone has an unpublished draft of the app open in the console, the deploy builds on that
draft instead of discarding it, and the log says so.

Runs on Linux and macOS runners, x64 and ARM64.

## License

Apache 2.0
