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
└── build-vulnmgmt.sh                          # Build/push vulnmgmt images to Quay
image-builds/
├── emojivoto/              # Vendored BuoyantIO/emojivoto source + Dockerfiles
├── base-ubi9-openjdk/      # Vulnmgmt shop-web base (UBI9 OpenJDK 17)
├── base-eap8/              # Vulnmgmt shop-api base (AMQ Streams Kafka, content manifests)
├── base-eap8-repacked/     # Negative control: Kafka JARs copied onto UBI (no content manifests)
├── shop-api/               # Shop API layers (download JARs; not committed)
└── shop-web/               # Shop Web layer on UBI OpenJDK
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

Rebuild and push (requires `podman login registry.redhat.io` and `podman login quay.io`):

```bash
make build-vulnmgmt
make push-vulnmgmt
make copy-vulnmgmt-prod-mirror
```

Deploy:

```bash
kubectl apply -f vulnmgmt/namespaces.yaml
kubectl apply -R -f vulnmgmt/
```

## Notes

- Some applications may require additional configuration or dependencies
- Routes are configured for OpenShift/Kubernetes ingress
- Check individual application directories for specific requirements
- These applications are intentionally vulnerable and should only be deployed in isolated environments
