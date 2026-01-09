# Skupper Demo Hummingbird - Local Podman Testing

This directory contains Podman-compatible manifests for testing the Skupper demo application locally using Podman.

## Prerequisites

- Podman installed and running
- `podman-compose` installed (or use `podman play kube` with Kubernetes YAML)

## Quick Start

### Option 1: Using podman-compose (Recommended)

1. Install podman-compose if not already installed:
   ```bash
   pip install podman-compose
   ```

2. Start all services:
   ```bash
   podman-compose up -d
   ```

3. View logs:
   ```bash
   podman-compose logs -f
   ```

4. Stop all services:
   ```bash
   podman-compose down
   ```

5. Stop and remove volumes:
   ```bash
   podman-compose down -v
   ```

### Option 2: Using podman play kube

If you prefer using Kubernetes YAML format, you can use the manifests from the parent `skuuper-demo` directory with `podman play kube`:

```bash
podman play kube database.yml frontend.yml payment.yml
```

## Services

The application consists of three services:

1. **Database** (PostgreSQL)
   - Port: `5432`
   - Container: `skupper-demo-database`
   - Uses hummingbird PostgreSQL base image

2. **Payment Processor**
   - Port: `8081` (host) -> `8080` (container)
   - Container: `skupper-demo-payment-processor`
   - Uses hummingbird Python base image

3. **Frontend**
   - Port: `8080` (host) -> `8080` (container)
   - Container: `skupper-demo-frontend`
   - Uses hummingbird Python base image
   - Accessible at: http://localhost:8080

## Accessing the Application

Once all services are running, access the frontend at:
- **Frontend**: http://localhost:8080
- **Payment Processor API**: http://localhost:8081

## Environment Variables

The frontend service is configured with the following environment variables:
- `DATABASE_SERVICE_HOST=database`
- `DATABASE_SERVICE_PORT=5432`
- `PAYMENT_PROCESSOR_SERVICE_HOST=payment-processor`
- `PAYMENT_PROCESSOR_SERVICE_PORT=8080`

## Database

The PostgreSQL database uses:
- User: `patient_portal`
- Password: `secret`
- Database: `patient_portal`
- Data is persisted in a Podman volume: `postgres_data`

## Troubleshooting

### Check service status
```bash
podman-compose ps
```

### View logs for a specific service
```bash
podman-compose logs database
podman-compose logs frontend
podman-compose logs payment-processor
```

### Restart a specific service
```bash
podman-compose restart frontend
```

### Remove everything and start fresh
```bash
podman-compose down -v
podman-compose up -d
```

### Check if ports are already in use
```bash
podman port skupper-demo-frontend
podman port skupper-demo-database
podman port skupper-demo-payment-processor
```

## Notes

- All services use images from `quay.io/skupper/patient-portal-*`
- The database includes a healthcheck to ensure it's ready before other services start
- Services are configured with restart policies to automatically restart on failure
- The network is isolated using a bridge network named `skupper-demo-network`
