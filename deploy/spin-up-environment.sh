#!/bin/bash

# this script is intended as idempotent setup for devops technical assignment

set -e

INSTALL_K3S="true"
INSTALL_HELM="true"
nodePort="${1:-32438}"
createCert="true"

ARTIFACT_DIR="/opt/tributech-artifacts"
CERT_DIR="$ARTIFACT_DIR/cert"
CERT_NAME="tributech-local-tls"
CERT_KEY="$CERT_DIR/tributech.key"
CERT_CRT="$CERT_DIR/tributech.crt"
DOMAINS=(keycloak.local website.local)
NAMESPACE="default"

UI_REPO_URL="https://github.com/tributech-solutions/tributech-ui-oauth-sample.git"
CLONE_DIR="$HOME/tributech-ui-oauth-sample"
IMAGE_NAME="tributech-ui-oauth-sample"
IMAGE_TAG="local"

echo "Ensuring artifact directory exists at $ARTIFACT_DIR"
mkdir -p "$CERT_DIR"

if [ "$INSTALL_K3S" == "true" ]; then
  if command -v k3s >/dev/null 2>&1 || systemctl is-active --quiet k3s; then
    echo "k3s is already installed and running."
  else
    echo "Installing k3s..."
    curl -sfL https://get.k3s.io | sh -
  fi
fi

if [ "$INSTALL_HELM" == "true" ]; then
  if command -v helm >/dev/null 2>&1; then
    echo "Helm is already installed."
  else
    echo "Installing Helm..."
    curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3
    chmod 700 get_helm.sh
    ./get_helm.sh
    rm get_helm.sh
  fi
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker not found. Installing via get.docker.com..."
  curl -fsSL https://get.docker.com | sh
fi


if [ -d "$CLONE_DIR" ]; then
  echo "UI repo already exists at $CLONE_DIR, deleting."
  rm -rf "$CLONE_DIR"
fi

echo "Cloning repository with website project..."
git clone "$UI_REPO_URL" "$CLONE_DIR"

ENV_FILE="$CLONE_DIR/src/environments/environment.ts"
if grep -q "https://auth.dev-x.tributech-node.com/realms/node" "$ENV_FILE"; then
  echo "Patching OAuth URL in environment.ts..."
  sed -i "s|https://auth.dev-x.tributech-node.com/realms/node|https://keycloak.local:$nodePort/realms/node|g" "$ENV_FILE"
fi

if docker image inspect "$IMAGE_NAME:$IMAGE_TAG" >/dev/null 2>&1; then
  echo "Docker image $IMAGE_NAME:$IMAGE_TAG already exists, deleting"
  docker rmi "$IMAGE_NAME:$IMAGE_TAG" || true
  k3s ctr images rm "$IMAGE_NAME:$IMAGE_TAG" || true
fi

echo "Building Docker image... This may take up to 3 minutes."
cd "$CLONE_DIR" || exit 1
docker build -t "$IMAGE_NAME:$IMAGE_TAG" .

echo "Importing image into containerd... This may take up to 2 minutes."
( docker save "$IMAGE_NAME:$IMAGE_TAG" | k3s ctr images import - ) &
IMPORT_PID=$!

while kill -0 $IMPORT_PID 2>/dev/null; do
  echo "Still importing..."
  sleep 10
done

wait $IMPORT_PID

if [ "$createCert" == "true" ]; then
  if [ -f "$CERT_KEY" ] || [ -f "$CERT_CRT" ]; then
    echo "Removing old certificate files..."
    rm -f "$CERT_KEY" "$CERT_CRT"
  fi

  if kubectl get secret "$CERT_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "Deleting existing Kubernetes secret '$CERT_NAME' from namespace '$NAMESPACE'..."
    kubectl delete secret "$CERT_NAME" -n "$NAMESPACE"
  fi

  SAN_LIST=$(printf "DNS:%s," "${DOMAINS[@]}")
  SAN_LIST=${SAN_LIST%,}

  echo "Generating self-signed certificate for: ${DOMAINS[*]}"
  openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout "$CERT_KEY" \
    -out "$CERT_CRT" \
    -subj "/CN=${DOMAINS[0]}" \
    -addext "subjectAltName=$SAN_LIST"

  echo "Creating Kubernetes TLS secret '$CERT_NAME' in namespace '$NAMESPACE'..."
  kubectl create secret tls "$CERT_NAME" \
    --cert="$CERT_CRT" \
    --key="$CERT_KEY" \
    --namespace "$NAMESPACE"

  echo "TLS secret '$CERT_NAME' created in namespace '$NAMESPACE'"
fi

echo "Completed! You can now go ahead and run helm install to spin up the application along with all the components. See the README file"