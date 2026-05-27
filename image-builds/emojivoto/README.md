# Emojivoto (image builds)

Vendored source from [BuoyantIO/emojivoto](https://github.com/BuoyantIO/emojivoto) (Apache-2.0): a small microservices app where **vote-bot** automatically generates traffic between `web` → `emoji-svc` / `voting-svc` over gRPC.

Images are published to **Quay** as `quay.io/<team>/emojivoto-*:<version>` (default `quay.io/mfoster/...:0.1.0`), matching other apps in this repo.

## Quay repositories

Create these repositories on your Quay organization (public or private):

| Repository | Used by |
|------------|---------|
| `emojivoto-svc-base` | Runtime base layer (built first) |
| `emojivoto-web` | `web` Deployment and `vote-bot` |
| `emojivoto-emoji-svc` | `emoji` Deployment |
| `emojivoto-voting-svc` | `voting` Deployment |

## Build prerequisites

- `podman` or `docker`, `make`, `go`, `curl`, `unzip`
- **`yarn`** (for `emojivoto-web` frontend bundle)
- **protoc**: `brew install protobuf` *or* the bundled `bin/protoc` (auto-downloads v25.1; fixes Apple Silicon — v3.18 had no `osx-arm64` zip, which caused curl error 56)

## Build and push to Quay

```bash
# Login (robot account or user with push access)
podman login quay.io

cd image-builds/emojivoto
chmod +x build-images.sh

# Build only (tags under quay.io/mfoster by default)
./build-images.sh

# Build and push
PUSH=1 ./build-images.sh
```

Custom org or version:

```bash
TEAM_NAME=myorg VERSION=0.2.0 PUSH=1 ./build-images.sh
# or
REGISTRY_PREFIX=quay.io/myorg IMAGE_TAG=0.2.0 PUSH=1 ./build-images.sh
```

From repo root (uses `TEAM_NAME` / `VERSION` from root `makefile`):

```bash
make build-emojivoto
make push-emojivoto
make build-push-emojivoto   # build + push
```

Optional config file:

```bash
cp quay.env.example quay.env   # edit TEAM_NAME, VERSION
source quay.env && PUSH=1 ./build-images.sh
```

## Deploy

Manifests use **public upstream images** (no Quay build required):

```bash
kubectl apply -f k8s-deployment-manifests/-namespaces/namespace-emojivoto.yaml
kubectl apply -f k8s-deployment-manifests/emojivoto/
```

Images: `docker.l5d.io/buoyantio/emojivoto-{web,emoji-svc,voting-svc}:v11` (same as [Buoyant kustomize](https://github.com/BuoyantIO/emojivoto/kustomize/deployment)).

After building and pushing to your Quay org:

```bash
make update-emojivoto-manifests TEAM_NAME=myorg VERSION=0.1.0
kubectl apply -f k8s-deployment-manifests/emojivoto/
```

OpenShift route:

```bash
kubectl apply -f k8s-deployment-manifests/emojivoto/route-emojivoto.yaml
```

**Private repos:** create an image pull secret in namespace `emojivoto` and add `imagePullSecrets` to the Deployments in `everything.yml`.

Verify automatic traffic:

```bash
kubectl get pods -n emojivoto
kubectl logs -n emojivoto deploy/vote-bot -f
```

## Dockerfiles

| File | Purpose |
|------|---------|
| `Dockerfile-base` | Runtime base (debian + curl, jq, …) |
| `Dockerfile` | Per-service image (`BASE_IMAGE`, `svc_name` build args) |
| `Dockerfile-multi-arch` | Multi-arch buildx variant |

## Manual build (Makefile)

```bash
export REGISTRY_PREFIX=quay.io/mfoster IMAGE_TAG=0.1.0 CONTAINER_CMD=podman
make build-base-docker-image
make -C emojivoto-web build-container
make -C emojivoto-emoji-svc build-container
make -C emojivoto-voting-svc build-container
make push   # pushes all four images when REGISTRY_PREFIX is set
```
