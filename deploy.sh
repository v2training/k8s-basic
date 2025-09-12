# Deploy script
# deploy.sh
#!/bin/bash

# Build and push Docker images
echo "Building Docker images..."

# Build backend
docker build -t your-registry/backend-api:latest ./backend
docker push your-registry/backend-api:latest

# Build frontend
docker build -t your-registry/frontend-app:latest ./frontend
docker push your-registry/frontend-app:latest

# Apply Kubernetes manifests
echo "Deploying to AKS..."
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/backend-deployment.yaml
kubectl apply -f k8s/backend-service.yaml
kubectl apply -f k8s/frontend-deployment.yaml
kubectl apply -f k8s/frontend-service.yaml
kubectl apply -f k8s/configmap.yaml
kubectl apply -f k8s/hpa.yaml

# Optional: Apply ingress if you have nginx-ingress controller
# kubectl apply -f k8s/ingress.yaml

echo "Deployment complete!"
echo "Check status with: kubectl get pods -n microservice-demo"
echo "Get service URL with: kubectl get svc -n microservice-demo"