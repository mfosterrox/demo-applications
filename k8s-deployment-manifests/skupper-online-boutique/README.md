# Skupper Online Boutique Demo

This directory contains manifests for deploying the Online Boutique demo application across multiple namespaces using Skupper for service mesh connectivity.

## Prerequisites

**Skupper CRDs must be installed before deploying these resources.**

### Quick Install

Run the installation script to install Skupper CRDs:

```bash
chmod +x 00-install-skupper-crds.sh
./00-install-skupper-crds.sh
```

Or manually install Skupper:

**Cluster-scoped installation:**
```bash
kubectl apply -f https://github.com/skupperproject/skupper/releases/download/2.1.3/skupper-cluster-scope.yaml
```

**Namespace-scoped installation:**
```bash
kubectl apply -f https://github.com/skupperproject/skupper/releases/download/2.1.3/skupper-namespace-scope.yaml
```

### Verify CRDs are Installed

```bash
kubectl get crd | grep skupper
```

You should see:
- `sites.skupper.io`
- `serviceexports.skupper.io`
- `connectors.skupper.io` (v2alpha1)
- `listeners.skupper.io` (v2alpha1)

## Deployment Structure

- **namespace-grpc-*.yaml**: Namespace definitions for grpc-a, grpc-b, grpc-c
- **resources-a/**: Resources for namespace grpc-a (frontend, product catalog, currency, recommendation, ad services)
- **resources-b/**: Resources for namespace grpc-b (cart, checkout services)
- **resources-c/**: Resources for namespace grpc-c (shipping, payment, email services)

## Deployment Order

1. Install Skupper CRDs (see above)
2. Deploy namespaces:
   ```bash
   kubectl apply -f namespace-grpc-a.yaml
   kubectl apply -f namespace-grpc-b.yaml
   kubectl apply -f namespace-grpc-c.yaml
   ```
3. Deploy resources in order:
   ```bash
   kubectl apply -R -f resources-a/
   kubectl apply -R -f resources-b/
   kubectl apply -R -f resources-c/
   ```

## Notes

- The manifests use `skupper.io/v1alpha1` API version
- Skupper Sites are created in each namespace to enable connectivity
- ServiceExports expose services across the Skupper network
- For more information, see: https://skupper.io/
