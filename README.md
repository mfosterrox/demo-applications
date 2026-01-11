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
kubectl get namespaces | grep -E "(apache-struts|dvwa|juice-shop|log4shell|nodejs-goof|patient-portal|unprotected-api|web-ctf|webgoat)"

# Check pods across all demo namespaces
kubectl get pods --all-namespaces | grep -E "(apache-struts|dvwa|juice-shop|log4shell|nodejs-goof|patient-portal|unprotected-api|web-ctf|webgoat)"

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

- **apache-struts** - Apache Struts vulnerable application
- **dvwa** - Damn Vulnerable Web Application
- **dvwa-hummingbird** - DVWA with Hummingbird integration
- **juice-shop** - OWASP Juice Shop
- **log4shell** - Log4Shell vulnerability demonstration
- **medical-application** - Patient Portal medical application
- **nodejs-goof-vuln-main** - Node.js Goof vulnerable application
- **skupper-demo** - Skupper demo application
- **skupper-demo-hummingbird** - Skupper demo with Hummingbird
- **web-ctf-container** - Web CTF container
- **webgoat** - OWASP WebGoat

## Directory Structure

```
k8s-deployment-manifests/
├── -namespaces/          # Namespace definitions
├── apache-struts/        # Apache Struts manifests
├── dvwa/                 # DVWA manifests
├── dvwa-hummingbird/     # DVWA Hummingbird manifests
├── juice-shop/           # Juice Shop manifests
├── log4shell/            # Log4Shell manifests
├── medical-application/  # Medical application manifests
├── nodejs-goof-vuln-main/# Node.js Goof manifests
├── skupper-demo/         # Skupper demo manifests
├── skupper-demo-hummingbird/ # Skupper Hummingbird manifests
├── web-ctf-container/    # Web CTF manifests
└── webgoat/              # WebGoat manifests
```

## Notes

- Some applications may require additional configuration or dependencies
- Routes are configured for OpenShift/Kubernetes ingress
- Check individual application directories for specific requirements
- These applications are intentionally vulnerable and should only be deployed in isolated environments
