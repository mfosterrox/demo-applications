# Demo Applications

A collection of vulnerable demo applications for security testing and educational purposes.

## Prerequisites

- Kubernetes cluster access (kubectl configured)
- Appropriate permissions to create namespaces, deployments, services, routes, etc.

## Quick Deploy

Clone the repository and deploy all applications in one command:

```bash
git clone https://github.com/mfosterrox/demo-applications.git && cd demo-applications && kubectl apply -R -f k8s-deployment-manifests/
```

## Quick Start - Deploy All Applications

Deploy all namespaces first, then all application manifests:

```bash
# Deploy all namespaces
kubectl apply -f k8s-deployment-manifests/-namespaces/

# Deploy all applications
kubectl apply -R -f k8s-deployment-manifests/
```

Or deploy everything in one command (namespaces will be created automatically):

```bash
kubectl apply -R -f k8s-deployment-manifests/
```

## Verify Deployments

Check the status of all deployments:

```bash
# List all namespaces
kubectl get namespaces | grep -E "(acs-fam-demo|apache-struts|dvwa|emojivoto|juice-shop|log4shell|nodejs-goof|patient-portal|unprotected-api|web-ctf|webgoat)"

# Check pods across all demo namespaces
kubectl get pods --all-namespaces | grep -E "(acs-fam-demo|apache-struts|dvwa|emojivoto|juice-shop|log4shell|nodejs-goof|patient-portal|unprotected-api|web-ctf|webgoat)"

# Check deployments in a specific namespace
kubectl get deployments -n juice-shop
```

## Cleanup

### Remove All Applications

```bash
# Delete all application resources (excluding namespaces)
kubectl delete -R -f k8s-deployment-manifests/ --ignore-not-found=true

# Delete all namespaces (this will also delete all resources within them)
kubectl delete -f k8s-deployment-manifests/-namespaces/ --ignore-not-found=true
```

### Remove Individual Application

```bash
# Example: Remove Juice Shop
kubectl delete -f k8s-deployment-manifests/juice-shop/ --ignore-not-found=true
kubectl delete namespace juice-shop --ignore-not-found=true
```

## Available Applications

- **acs-fam-demo** - UBI keep-alive workload for RHACS File Activity Monitoring (FAM) labs
- **apache-struts** - Apache Struts vulnerable application
- **dvwa** - Damn Vulnerable Web Application
- **dvwa-hummingbird** - DVWA with Hummingbird integration
- **hummingbird-demo** - Project Hummingbird Python base + layered app (RHACS base vs application CVE demo)
- **java-patch-demo** - Three Spring Boot builds of one app: Lightwell on hardened OpenJDK, plus public OpenJDK images about six months and one year old
- **emojivoto** - Buoyant emoji voting demo (mirror to Quay: `make mirror-emojivoto-to-quay`; vote-bot generates traffic)
- **juice-shop** - OWASP Juice Shop
- **log4shell** - Log4Shell vulnerability demonstration
- **medical-application** - Patient Portal medical application
- **nodejs-goof-vuln-main** - Node.js Goof vulnerable application
- **skupper-demo** - Skupper demo application
- **skupper-demo-hummingbird** - Skupper demo with Hummingbird
- **vulnmgmt** - RHACS vulnerability-management shop demo (dev/stage/prod + platform negative control)
- **web-ctf-container** - Web CTF container
- **webgoat** - OWASP WebGoat

## Directory Structure

```
k8s-deployment-manifests/
├── -namespaces/          # Namespace definitions
├── acs-fam-demo/         # UBI FAM trigger (fam-target)
├── apache-struts/        # Apache Struts manifests
├── dvwa/                 # DVWA manifests
├── dvwa-hummingbird/     # DVWA Hummingbird manifests
├── hummingbird-demo/     # Hummingbird Python base + layered deployment (Quay image)
├── java-patch-demo/      # Lightwell / 6mo / 1yr Spring Boot (one namespace, three routes)
├── emojivoto/            # Emojivoto (web, emoji, voting, vote-bot)
├── juice-shop/           # Juice Shop manifests
├── log4shell/            # Log4Shell manifests
├── medical-application/  # Medical app (matches demo-apps layout)
│   ├── backend/everything.yml
│   ├── frontend/everything.yml
│   ├── medical/everything.yml
│   ├── operations/everything.yml
│   └── payments/everything.yml
├── nodejs-goof-vuln-main/# Node.js Goof manifests
├── skupper-demo/         # Skupper demo manifests
├── skupper-demo-hummingbird/ # Skupper Hummingbird manifests
├── web-ctf-container/    # Web CTF manifests
└── webgoat/              # WebGoat manifests
vulnmgmt/                 # Opt-in RHACS shop demo (not under k8s-deployment-manifests)
scripts/
├── medical-application-netflow-flows.sh       # Shared -connect flow definitions
├── generate-medical-application-traffic.sh  # Exec into pods; dial -connect targets
├── verify-medical-application-network.sh    # Post-deploy pod-to-pod flow check
├── build-vulnmgmt.sh                          # Build/push vulnmgmt images to Quay
├── build-java-patch-6mo-1yr.sh                # Build/push the 6mo and 1yr Java images
├── build-java-patch-lightwell.sh              # Build/push the Lightwell image; prompts for credentials
└── quay-reuse.sh                              # Skip rebuild/push when Quay already has the tag
image-builds/
├── emojivoto/              # Vendored BuoyantIO/emojivoto source + Dockerfiles
├── base-ubi9-openjdk/      # Vulnmgmt shop-web base (UBI9 OpenJDK 17)
├── base-eap8/              # Vulnmgmt shop-api base (AMQ Streams Kafka, content manifests)
├── base-eap8-repacked/     # Negative control: Kafka JARs copied onto UBI (no content manifests)
├── shop-api/               # Shop API layers (download JARs; not committed)
├── shop-web/               # Shop Web layer on UBI OpenJDK
└── java-patch-demo/        # Shared Java source; lightwell, 6mo, and 1yr Containerfiles
```

## RHACS vulnerability management (vulnmgmt)

Shop demo images and workloads for RHACS vulnerability-management labs. Manifests live in `vulnmgmt/` (repo root), not under `k8s-deployment-manifests/`, so a bulk apply of default workshop manifests does not deploy shop stages. Image refs are `quay.io/mfoster`.

Images:

- `quay.io/mfoster/base-ubi9-openjdk:1.0` - shop-web base
- `quay.io/mfoster/base-eap8:1.0` - shop-api base (Red Hat product with content manifests)
- `quay.io/mfoster/base-eap8-repacked:1.0` - negative control (JARs copied, no content manifests)
- `quay.io/mfoster/shop-api:1.0.0` - vulnerable Log4j 2.14.1 + commons-text 1.9 (also tagged `feature-x-abc1234`)
- `quay.io/mfoster/shop-api:1.1.0` - patched Log4j 2.17.1
- `quay.io/mfoster/shop-web:1.0.0`
- `quay.io/mfoster/prod-mirror-shop-api:1.0.0` / `prod-mirror-shop-web:1.0.0` - same digest as the `1.0.0` shop images

JARs are gitignored. Download them before a local build:

```bash
./image-builds/shop-api/download-jars.sh
```

Rebuild and push (requires `podman login registry.redhat.io` and `podman login quay.io`). These images are also included in `make build-tag-and-push`.

```bash
make build-vulnmgmt
make push-vulnmgmt
make copy-vulnmgmt-prod-mirror
```

Deploy:

```bash
kubectl apply -f vulnmgmt/namespaces.yaml
kubectl wait --for=jsonpath='{.status.phase}'=Active namespace/demo-dev namespace/demo-stage namespace/demo-prod namespace/demo-platform --timeout=90s
kubectl apply -R -f vulnmgmt/
```

## Java patch-age demo

One Spring Boot application, three independent images. Each cohort has its own Containerfile, pom, and OpenShift manifest. The build scripts do not pass base images or library versions. Edit the cohort file, then rebuild that image.

The lightwell cohort resolves Java artifacts from the Red Hat Lightwell Network remediated repository, then the validated repository, then Maven Central. The repository profile is in `image-builds/java-patch-demo/lightwell/settings.xml`. `scripts/build-java-patch-lightwell.sh` uses an existing `image-builds/podman-build-secret-*` file when one is present. Otherwise it prompts for the registry service account username (`orgId|name`) and access token and saves `image-builds/podman-build-secret-lightwell`. That file is gitignored. Delete it to enter a new token. The token is mounted only for the Maven build and is not stored in the image.

| Cohort | Containerfile and libraries | Deployment |
| --- | --- | --- |
| lightwell | `image-builds/java-patch-demo/lightwell/` — `hi/openjdk:latest`, Spring Boot 4.1.1, Jackson 3.1.7 | `k8s-deployment-manifests/java-patch-demo/java-patch-lightwell.yaml` |
| 6mo | `image-builds/java-patch-demo/6mo/` — UBI9 OpenJDK 21 from 2026-05-04, Spring Boot 4.0.6 | `k8s-deployment-manifests/java-patch-demo/java-patch-6mo.yaml` |
| 1yr | `image-builds/java-patch-demo/1yr/` — UBI9 OpenJDK 21 from 2025-12-03, Spring Boot 3.5.8 | `k8s-deployment-manifests/java-patch-demo/java-patch-1yr.yaml` |

Images (`quay.io/mfoster`, override the org with `TEAM_NAME`):

- `quay.io/mfoster/java-patch-demo:lightwell`
- `quay.io/mfoster/java-patch-demo:6mo`
- `quay.io/mfoster/java-patch-demo:1yr`

Build and push to `quay.io/mfoster` (requires `podman login quay.io`). The Lightwell command prompts for the username and access token.

```bash
make java-patch-6mo-1yr
make java-patch-lightwell

# Rebuild and push one older cohort after editing its Containerfile or pom.
make java-patch-6mo-1yr JAVA_PATCH_COHORT=6mo
```

`make build-java-patch-6mo-1yr` and `make build-java-patch-lightwell` build locally and skip the push. Running either script with no arguments also builds and pushes.

Deploy all three into namespace `java-patch-demo`. Each file includes a Deployment, Service, and Route.

```bash
kubectl apply -f k8s-deployment-manifests/-namespaces/namespace-java-patch-demo.yaml
kubectl apply -f k8s-deployment-manifests/java-patch-demo/
```

`GET /` on each route returns the patch tag, the Spring Boot version from that image's pom, and the Java version. Probes use `GET /health`.

## Notes

- Some applications may require additional configuration or dependencies
- Routes are configured for OpenShift/Kubernetes ingress
- Check individual application directories for specific requirements
- These applications are intentionally vulnerable and should only be deployed in isolated environments
