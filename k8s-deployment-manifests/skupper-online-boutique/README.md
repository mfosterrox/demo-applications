# Skupper Online Boutique Example

This directory contains Kubernetes manifests for deploying the Online Boutique gRPC microservices application across multiple namespaces/clusters using Skupper.

## Overview

The Online Boutique is a cloud-native microservices demo application that consists of 10+ microservices written in different languages. This example demonstrates how to deploy these services across multiple namespaces (grpc-a, grpc-b, grpc-c) and connect them using Skupper.

## Structure

- `namespace-grpc-a.yaml`, `namespace-grpc-b.yaml`, `namespace-grpc-c.yaml` - Namespace definitions
- `resources-a/` - Services deployed to grpc-a namespace (frontend, product-catalog, currency, recommendation, ad)
- `resources-b/` - Services deployed to grpc-b namespace (cart, checkout, redis)
- `resources-c/` - Services deployed to grpc-c namespace (shipping, payment, email)

## Deployment

### Prerequisites

1. Skupper must be installed on your cluster:
   ```bash
   kubectl apply -f https://skupper.io/v2/install.yaml
   ```

2. Install the Skupper CLI:
   ```bash
   curl https://skupper.io/install.sh | sh
   ```

### Deploy Resources

Deploy all namespaces and resources:

```bash
# Deploy namespaces
kubectl apply -f namespace-grpc-a.yaml
kubectl apply -f namespace-grpc-b.yaml
kubectl apply -f namespace-grpc-c.yaml

# Deploy resources for each site
kubectl apply -f resources-a/
kubectl apply -f resources-b/
kubectl apply -f resources-c/
```

### Link Sites with Skupper

After deploying, link the sites using Skupper tokens:

```bash
# Generate token from grpc-a
skupper token issue ~/grpc-a.token --redemptions-allowed=2 -n grpc-a

# Link grpc-b to grpc-a
skupper token redeem ~/grpc-a.token -n grpc-b

# Link grpc-c to grpc-a
skupper token redeem ~/grpc-a.token -n grpc-c
```

## Services

### grpc-a Namespace
- **frontend** - Web frontend (port 8080)
- **productcatalogservice** - Product catalog gRPC service (port 3550)
- **currencyservice** - Currency conversion service (port 7000)
- **recommendationservice** - Product recommendations (port 8080)
- **adservice** - Advertisement service (port 9555)

### grpc-b Namespace
- **cartservice** - Shopping cart service (port 7070)
- **redis-cart** - Redis cache for cart (port 6379)
- **checkoutservice** - Checkout processing (port 5050)

### grpc-c Namespace
- **shippingservice** - Shipping calculation gRPC service (port 50051)
- **paymentservice** - Payment processing gRPC service (port 50051)
- **emailservice** - Email notifications (port 5000)

## Accessing the Application

After deployment and linking, access the frontend via the route:

```bash
oc get route frontend -n grpc-a
```

## Cleanup

To remove all resources:

```bash
kubectl delete -f resources-a/
kubectl delete -f resources-b/
kubectl delete -f resources-c/
kubectl delete -f namespace-grpc-a.yaml
kubectl delete -f namespace-grpc-b.yaml
kubectl delete -f namespace-grpc-c.yaml
```
