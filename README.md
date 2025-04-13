# Serverless Compute - APISIX, Nuclio and MinIO on Minikube

This guide sets up a local serverless environment using Minikube, integrating Apache APISIX as the gateway, MinIO for
object storage, and Nuclio for serverless functions. <br>
The system supports function uploads and deployments via a custom APISIX route.

## Prerequisites

- **Minikube**: Install [Minikube](https://minikube.sigs.k8s.io/docs/start/).
- **kubectl**: Install [kubectl](https://kubernetes.io/docs/tasks/tools/).
- **Helm**: Install [Helm](https://helm.sh/docs/intro/install/).
- **Docker**: Required for Minikube’s driver.

## Setup Minikube

1. **Start Minikube** with sufficient resources:
   ```bash
   export DOCKER_DEFAULT_PLATFORM=linux/arm64
   minikube start --memory 4096 --cpus 2 --driver=docker
   ```

2. **Enable Addons**:
   ```bash
   minikube addons enable storage-provisioner
   minikube addons enable ingress
   minikube addons enable registry
   minikube addons enable metrics-server
   ```

3. **Set Docker Environment**:
   ```bash
   eval $(minikube docker-env)
   ```

4. **Verify Cluster**:
   ```bash
   kubectl get nodes
   kubectl get pods
   ```

5. **Verify Registry**:
   ```bash
   nohup kubectl port-forward --namespace kube-system svc/registry 5000:80 > registry-port-forward.log 2>&1 &
   curl http://localhost:5000/v2/_catalog
   ```

## Create Namespace

1. **Apply Namespace**:
   ```bash
   kubectl apply -f serverless-config/namespace.yaml
   ```
   Content: [namespace.yaml](serverless-config/namespace.yaml)

2. **Set Context**:
   ```bash
   kubectl config set-context --current --namespace=serverless
   ```

## Deploy Components

### MinIO (Object Storage)

1. **Add Helm Repo**:
   ```bash
   helm repo add minio https://charts.min.io/
   helm repo update
   ```

2. **Install MinIO**:
   ```bash
   helm install minio minio/minio -f serverless-config/minio-values.yaml
   ```
   Content: [minio-values.yaml](serverless-config/minio-values.yaml)

### Nuclio (Serverless Platform)

1. **Add Helm Repo**:
   ```bash
   helm repo add nuclio https://nuclio.github.io/nuclio/charts
   helm repo update
   ```

2. **Install Nuclio**:
   ```bash
   helm install nuclio nuclio/nuclio -f serverless-config/nuclio-values.yaml
   ```
   Content: [nuclio-values.yaml](serverless-config/nuclio-values.yaml)

### APISIX (API Gateway)

1. **Add Helm Repos**:
   ```bash
   helm repo add apisix https://charts.apiseven.com
   helm repo add bitnami https://charts.bitnami.com/bitnami
   helm repo update
   ```

2. **Install APISIX**:
   ```bash
   helm install apisix apisix/apisix -f serverless-config/apisix-values.yaml
   kubectl get pods
   ```
   All pods must be running before starting to next steps.<br>
   Content: [apisix-values.yaml](serverless-config/apisix-values.yaml)

## Port Forwarding

Expose services locally:

```bash
nohup kubectl port-forward svc/minio 9000:9000 > minio-port-forward.log 2>&1 &
nohup kubectl port-forward svc/minio-console 9001:9001 > minio-console-port-forward.log 2>&1 &
nohup kubectl port-forward svc/nuclio-dashboard 8070:8070 > nuclio-dashboard-port-forward.log 2>&1 &
nohup kubectl port-forward svc/apisix-gateway 8080:80 > apisix-gateway-port-forward.log 2>&1 &
nohup kubectl port-forward svc/apisix-dashboard 8082:80 > apisix-dashboard-port-forward.log 2>&1 &
```

## Configure Function Upload

1. **Copy Lua Script (Function Deployment Utility)**:
   ```bash
   kubectl cp serverless-config/upload_function.lua $(kubectl get pods -l app.kubernetes.io/name=apisix -o name | head -n 1 | cut -d'/' -f2):/usr/local/apisix/upload_function.lua
   ```
   Content: [upload_function.lua](serverless-config/upload_function.lua)

2. **Apply APISIX Route**:
   ```bash
   kubectl apply -f serverless-config/apisix-routes.yaml
   ```
   Content: [apisix-routes.yaml](serverless-config/apisix-routes.yaml)

## Deploy a Function and Test

1. **Serverless function - Python 3.9 with environment variable**:
   ```bash
   # Create payload and deploy function
   base64 -i example-functions/greeting-user.zip | (echo -n '{"metadata":{"name":"greeting-user"},"spec":{"runtime":"python:3.9","handler":"function:handler","env":[{"name":"DEFAULT_USER","value":"ENV User"}],"build":{"commands":["pip install msgpack"]}},"zip_data":"' && cat - && echo -n '"}') > payload.json
   curl -X POST -H "Content-Type: application/json" --data @payload.json "http://127.0.0.1:8080/upload-function"
   # Invoke function with payload and without payload
   curl -X POST "http://127.0.0.1:8080/invoke" \
     -H "x-nuclio-function-name: greeting-user" \
     -H "Content-Type: application/json" \
     -d '{"name": "Vinod"}'
   curl -X POST "http://127.0.0.1:8080/invoke" \
     -H "x-nuclio-function-name: greeting-user" \
     -H "Content-Type: application/json"
   ```

2. **Serverless function - Python 3.11 with dependencies**:
   ```bash
   # Create payload and deploy function
   base64 -i example-functions/currency-converter.zip | (echo -n '{"metadata":{"name":"currency-converter"},"spec":{"runtime":"python:3.11","handler":"handler:handler","build":{"commands":["pip install msgpack requests"]}},"zip_data":"' && cat - && echo -n '"}') > payload.json
   curl -X POST -H "Content-Type: application/json" --data @payload.json "http://127.0.0.1:8080/upload-function"
   # Invoke function
   curl -X POST "http://127.0.0.1:8080/invoke" \
     -H "x-nuclio-function-name: currency-converter" \
     -H "Content-Type: application/json" \
     -d '{"base_currency": "USD", "target_currency": "SGD", "amount": "100"}'
   ```

3. **Serverless function - Nodejs with dependencies**:
   ```bash
   # Create payload and deploy function
   base64 -i example-functions/greeting-node.zip | (echo -n '{"metadata":{"name":"greeting-node"},"spec":{"runtime":"nodejs","handler":"main:handler","env":[{"name":"DEFAULT_USER","value":"Node User"}],"build":{"commands":["npm install --global uuid@8.3.2"]}},"zip_data":"' && cat - && echo -n '"}') > payload.json 
   curl -X POST -H "Content-Type: application/json" --data @payload.json "http://127.0.0.1:8080/upload-function"
   # Invoke function
   curl -X POST "http://127.0.0.1:8080/invoke" \
     -H "x-nuclio-function-name: greeting-node" \
     -H "Content-Type: application/json" \
     -d '{"name": "Vinod"}'
   ```

4. **Load Test - Auto-Scaling**:
   ```bash
   python nuclio_load_test.py --threads 50 --requests-per-thread 300 --function-name currency-converter --url http://127.0.0.1:8080/invoke
   kubectl top pods  | grep currency-converter
   ```
   Content: [nuclio_load_test.py](nuclio_load_test.py)

## Cleanup

1. **Stop Port Forwards**:
   ```bash
   kill $(ps aux | grep "kubectl port-forward" | grep -v grep | awk '{print $2}')
   rm *.log
   rm payload.json 
   ```

2. **Remove Resources**:
   ```bash
   kubectl delete -f serverless-config/apisix-routes.yaml
   helm uninstall minio -n serverless
   helm uninstall nuclio -n serverless
   helm uninstall apisix -n serverless
   kubectl delete namespace serverless
   ```

3. **Stop Minikube**:
   ```bash
   minikube stop
   minikube delete
   minikube cache delete
   rm -rf ~/.minikube/cache/
   eval $(minikube docker-env -u)
   ```

## Troubleshooting

- **Pod Issues**: Check logs with `kubectl logs <pod-name>`.
- **MinIO Dashboard**: Access at `http://localhost:9001` (Use `minioadmin:minioadmin123`).
- **Nuclio Dashboard**: Access at `http://localhost:8070`.
- **APISIX Dashboard**: Access at `http://localhost:8082` (Use `admin:admin`).