# deploy.ps1
# PowerShell deployment script for AKS microservice architecture
# This script builds Docker images, pushes them to Azure Container Registry,
# and deploys the application to an AKS cluster using kubectl.

# Ensure your logged in to Azure CLI and kubectl is configured to your AKS cluster
##### Azure Login - For Example: az login
##### Azure Container Registry Login - For Example: az acr login --name <RegistryName>
##### AKS Login - For Example: az aks get-credentials --resource-group <ResourceGroupName> --name <AKSClusterName>
#
# Usage: ./deploy.ps1


# Set error action preference
$ErrorActionPreference = "Stop"

# Function to check if command exists
function Test-CommandExists {
    param($command)
    $null = Get-Command $command -ErrorAction SilentlyContinue
    return $?
}

Write-Host "Starting deployment to AKS..." -ForegroundColor Green

# Check prerequisites
Write-Host "Checking prerequisites..." -ForegroundColor Yellow

if (-not (Test-CommandExists "docker")) {
    Write-Error "Docker is not installed or not in PATH"
    exit 1
}

if (-not (Test-CommandExists "kubectl")) {
    Write-Error "kubectl is not installed or not in PATH"
    exit 1
}

if (-not (Test-CommandExists "az")) {
    Write-Error "Azure CLI is not installed or not in PATH"
    exit 1
}

# Verify Azure login
Write-Host "Verifying Azure authentication..." -ForegroundColor Yellow
try {
    $account = az account show --query "name" -o tsv
    Write-Host "Logged in to Azure account: $account" -ForegroundColor Green
}
catch {
    Write-Error "Not logged into Azure. Please run 'az login' first."
    exit 1
}

# Verify kubectl connection
Write-Host "Verifying Kubernetes connection..." -ForegroundColor Yellow
try {
    $cluster = kubectl config current-context
    Write-Host "Connected to cluster: $cluster" -ForegroundColor Green
}
catch {
    Write-Error "kubectl not connected to cluster. Please run 'az aks get-credentials' first."
    exit 1
}

# Check if NGINX Ingress Controller is installed
Write-Host "Checking for NGINX Ingress Controller..." -ForegroundColor Yellow
$ingressPods = kubectl get pods -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx --ignore-not-found=true -o name
if (-not $ingressPods) {
    Write-Host "NGINX Ingress Controller not found. Installing..." -ForegroundColor Cyan
    
    try {
        Write-Host "Installing NGINX Ingress Controller..." -ForegroundColor Yellow
        kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
        if ($LASTEXITCODE -ne 0) { throw "Failed to install NGINX Ingress Controller" }
        
        Write-Host "Waiting for Ingress Controller to be ready..." -ForegroundColor Yellow
        kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=300s
        if ($LASTEXITCODE -ne 0) { 
            Write-Warning "Timeout waiting for Ingress Controller. It may still be starting up."
        } else {
            Write-Host "NGINX Ingress Controller is ready!" -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to install NGINX Ingress Controller: $_"
        exit 1
    }
} else {
    Write-Host "NGINX Ingress Controller is already installed." -ForegroundColor Green
}

# Build and push Docker images
Write-Host "Building and pushing Docker images..." -ForegroundColor Cyan

try {
    # Build backend
    Write-Host "Building backend image..." -ForegroundColor Yellow
    docker build -t kangarooreg.azurecr.io/backend-api:latest ./backend
    if ($LASTEXITCODE -ne 0) { throw "Backend build failed" }
    
    Write-Host "Pushing backend image..." -ForegroundColor Yellow
    docker push kangarooreg.azurecr.io/backend-api:latest
    if ($LASTEXITCODE -ne 0) { throw "Backend push failed" }
    
    # Build frontend
    Write-Host "Building frontend image..." -ForegroundColor Yellow
    docker build -t kangarooreg.azurecr.io/frontend-app:latest ./frontend
    if ($LASTEXITCODE -ne 0) { throw "Frontend build failed" }
    
    Write-Host "Pushing frontend image..." -ForegroundColor Yellow
    docker push kangarooreg.azurecr.io/frontend-app:latest
    if ($LASTEXITCODE -ne 0) { throw "Frontend push failed" }
    
    Write-Host "Docker images built and pushed successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Failed to build/push Docker images: $_"
    exit 1
}

# Apply Kubernetes manifests
Write-Host "Deploying to AKS..." -ForegroundColor Cyan

try {
    # Apply manifests in order
    $manifests = @(
        "k8s/namespace.yaml",
        "k8s/configmap.yaml",
        "k8s/backend-deployment.yaml",
        "k8s/backend-service.yaml",
        "k8s/frontend-deployment.yaml",
        "k8s/frontend-service.yaml",
        "k8s/hpa.yaml"
    )
    
    foreach ($manifest in $manifests) {
        if (Test-Path $manifest) {
            Write-Host "Applying $manifest..." -ForegroundColor Yellow
            kubectl apply -f $manifest
            if ($LASTEXITCODE -ne 0) { throw "Failed to apply $manifest" }
        } else {
            Write-Warning "Manifest file $manifest not found, skipping..."
        }
    }
    
    # Apply ingress (now automatically since we have ingress controller)
    if (Test-Path "k8s/ingress.yaml") {
        Write-Host "Applying ingress configuration..." -ForegroundColor Yellow
        kubectl apply -f k8s/ingress.yaml
        if ($LASTEXITCODE -ne 0) { throw "Failed to apply ingress" }
        Write-Host "Ingress applied successfully!" -ForegroundColor Green
    } else {
        Write-Warning "ingress.yaml not found. You'll need to create this file for proper routing."
    }
    
    Write-Host "Kubernetes manifests applied successfully!" -ForegroundColor Green
}
catch {
    Write-Error "Failed to apply Kubernetes manifests: $_"
    exit 1
}

# Wait for deployments to be ready
Write-Host "Waiting for deployments to be ready..." -ForegroundColor Cyan
try {
    kubectl wait --for=condition=available --timeout=300s deployment/backend-api -n microservice-demo
    kubectl wait --for=condition=available --timeout=300s deployment/frontend-app -n microservice-demo
    Write-Host "Deployments are ready!" -ForegroundColor Green
}
catch {
    Write-Warning "Timeout waiting for deployments. Check status manually."
}

# Wait for Ingress to get external IP
Write-Host "Waiting for Ingress to get external IP..." -ForegroundColor Cyan
$maxAttempts = 30
$attempt = 0
$ingressIP = ""

while ($attempt -lt $maxAttempts -and -not $ingressIP) {
    $attempt++
    Write-Host "Attempt $attempt of $maxAttempts..." -ForegroundColor Yellow
    
    try {
        $ingressInfo = kubectl get ingress microservice-ingress -n microservice-demo -o jsonpath='{.status.loadBalancer.ingress[0].ip}' --ignore-not-found=true
        if ($ingressInfo -and $ingressInfo -ne "<no value>") {
            $ingressIP = $ingressInfo
            break
        }
    }
    catch {
        # Ignore errors and continue trying
    }
    
    Start-Sleep -Seconds 10
}

# Display status and next steps
Write-Host "`nDeployment completed successfully!" -ForegroundColor Green
Write-Host "===========================================" -ForegroundColor Green

# Show current status
Write-Host "`nCurrent status:" -ForegroundColor Cyan
kubectl get pods -n microservice-demo
kubectl get svc -n microservice-demo
kubectl get ingress -n microservice-demo

if ($ingressIP) {
    Write-Host "`n🎉 Your application is available at: http://$ingressIP" -ForegroundColor Green -BackgroundColor Black
    Write-Host "🎉 API endpoints available at: http://$ingressIP/api/users" -ForegroundColor Green -BackgroundColor Black
} else {
    Write-Host "`n⏳ Ingress IP not yet available. Run this command to check:" -ForegroundColor Yellow
    Write-Host "   kubectl get ingress -n microservice-demo --watch" -ForegroundColor Gray
}

Write-Host "`nNext steps:" -ForegroundColor Cyan
Write-Host "1. Check pod status:" -ForegroundColor White
Write-Host "   kubectl get pods -n microservice-demo" -ForegroundColor Gray

Write-Host "`n2. Check ingress status:" -ForegroundColor White
Write-Host "   kubectl get ingress -n microservice-demo" -ForegroundColor Gray

Write-Host "`n3. View application logs:" -ForegroundColor White
Write-Host "   kubectl logs -f deployment/frontend-app -n microservice-demo" -ForegroundColor Gray
Write-Host "   kubectl logs -f deployment/backend-api -n microservice-demo" -ForegroundColor Gray

Write-Host "`n4. Test the API directly:" -ForegroundColor White
if ($ingressIP) {
    Write-Host "   curl http://$ingressIP/api/users" -ForegroundColor Gray
} else {
    Write-Host "   curl http://[INGRESS-IP]/api/users" -ForegroundColor Gray
}

Write-Host "`n5. If you need to troubleshoot ingress:" -ForegroundColor White
Write-Host "   kubectl describe ingress microservice-ingress -n microservice-demo" -ForegroundColor Gray
Write-Host "   kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx" -ForegroundColor Gray

Write-Host "`nDeployment script completed!" -ForegroundColor Green