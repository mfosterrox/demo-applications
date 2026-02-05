#!/bin/bash
# Install Skupper CRDs and Controller
# This script installs the Skupper operator which provides the required CRDs

set -euo pipefail

SKUPPER_VERSION="${SKUPPER_VERSION:-2.1.3}"
INSTALL_SCOPE="${INSTALL_SCOPE:-cluster-scope}"

echo "Installing Skupper CRDs and Controller..."
echo "Version: $SKUPPER_VERSION"
echo "Scope: $INSTALL_SCOPE"

# Use oc if available (OpenShift), otherwise fall back to kubectl
KUBECTL_CMD="${KUBECTL_CMD:-oc}"
if ! command -v "$KUBECTL_CMD" >/dev/null 2>&1; then
    KUBECTL_CMD="kubectl"
fi

if [ "$INSTALL_SCOPE" = "cluster-scope" ]; then
    echo "Installing cluster-scoped Skupper..."
    $KUBECTL_CMD apply -f "https://github.com/skupperproject/skupper/releases/download/${SKUPPER_VERSION}/skupper-cluster-scope.yaml"
elif [ "$INSTALL_SCOPE" = "namespace-scope" ]; then
    echo "Installing namespace-scoped Skupper..."
    $KUBECTL_CMD apply -f "https://github.com/skupperproject/skupper/releases/download/${SKUPPER_VERSION}/skupper-namespace-scope.yaml"
else
    echo "Error: INSTALL_SCOPE must be 'cluster-scope' or 'namespace-scope'"
    exit 1
fi

echo "Waiting for Skupper CRDs to be available..."
$KUBECTL_CMD wait --for=condition=Established crd/sites.skupper.io --timeout=120s || true
$KUBECTL_CMD wait --for=condition=Established crd/serviceexports.skupper.io --timeout=120s || true
$KUBECTL_CMD wait --for=condition=Established crd/connectors.skupper.io --timeout=120s || true
$KUBECTL_CMD wait --for=condition=Established crd/listeners.skupper.io --timeout=120s || true

echo "Skupper CRDs installed successfully!"
echo ""
echo "To verify CRDs are installed:"
echo "  $KUBECTL_CMD get crd | grep skupper"
