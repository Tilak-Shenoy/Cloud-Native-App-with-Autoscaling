#!/bin/bash
set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="cloudapp"
ENVIRONMENT="dev"
AWS_REGION="us-west-2"
# Auto-detect registry configuration
if [ -f ".env.ecr" ]; then
    source .env.ecr
    DOCKER_REGISTRY="$ECR_URI"
    echo "Using AWS ECR: $FULL_IMAGE_URI"
elif [ -f ".env.dockerhub" ]; then
    source .env.dockerhub
    DOCKER_REGISTRY="$DOCKER_USERNAME"
    echo "Using Docker Hub: $FULL_IMAGE_URI"
elif [ -f ".env.local" ]; then
    source .env.local
    DOCKER_REGISTRY=""
    echo "Using local deployment: $LOCAL_IMAGE_URI"
else
    echo "❌ No registry configuration found!"
    echo "Please run one of the following setup scripts first:"
    echo "  ./scripts/setup-ecr.sh      (for AWS ECR)"
    echo "  ./scripts/setup-dockerhub.sh (for Docker Hub)"
    echo "  ./scripts/setup-local.sh    (for local deployment)"
    echo "Or run: ./scripts/setup-registry.sh (interactive setup)"
    exit 1
fi

echo -e "${BLUE}🚀 Cloud-Native Application Deployment Script${NC}"
echo "=================================================="

# Function to print status
print_status() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "\n${BLUE}Checking prerequisites...${NC}"
    
    # Check if required tools are installed
    tools=("terraform" "kubectl" "docker" "aws")
    for tool in "${tools[@]}"; do
        if command -v $tool &> /dev/null; then
            print_status "$tool is installed"
        else
            print_error "$tool is not installed. Please install it first."
            exit 1
        fi
    done
    
    # Check AWS credentials
    if aws sts get-caller-identity &> /dev/null; then
        print_status "AWS credentials are configured"
    else
        print_error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
}

# Function to build and push Docker image
build_and_push_image() {
    echo -e "\n${BLUE}Building and pushing Docker image...${NC}"
    
    IMAGE_TAG="${DOCKER_REGISTRY}/${PROJECT_NAME}:$(git rev-parse --short HEAD 2>/dev/null || echo 'latest')"
    
    # Build image
    docker build -t $IMAGE_TAG .
    print_status "Docker image built: $IMAGE_TAG"
    
    # Push image
    docker push $IMAGE_TAG
    print_status "Docker image pushed: $IMAGE_TAG"
    
    # Update deployment manifest with new image
    sed -i.bak "s|your-registry/cloudapp:latest|$IMAGE_TAG|g" k8s/deployment.yaml
    print_status "Deployment manifest updated with image: $IMAGE_TAG"
}

# Function to deploy infrastructure with Terraform
deploy_infrastructure() {
    echo -e "\n${BLUE}Deploying infrastructure with Terraform...${NC}"
    
    cd terraform
    
    # Initialize Terraform
    terraform init
    print_status "Terraform initialized"
    
    # Create terraform.tfvars if it doesn't exist
    if [[ ! -f terraform.tfvars ]]; then
        cat > terraform.tfvars << EOF
aws_region = "$AWS_REGION"
project_name = "$PROJECT_NAME"
environment = "$ENVIRONMENT"
db_password = "$(openssl rand -base64 32)"
EOF
        print_status "Created terraform.tfvars with random database password"
    fi
    
    # Plan infrastructure
    terraform plan -out=tfplan
    print_status "Terraform plan completed"
    
    # Apply infrastructure
    terraform apply tfplan
    print_status "Infrastructure deployed successfully"
    
    # Get outputs
    EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
    RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
    ALB_DNS_NAME=$(terraform output -raw load_balancer_dns)
    
    print_status "EKS Cluster: $EKS_CLUSTER_NAME"
    print_status "RDS Endpoint: $RDS_ENDPOINT"
    print_status "Load Balancer: $ALB_DNS_NAME"
    
    cd ..
}

# Function to configure kubectl
configure_kubectl() {
    echo -e "\n${BLUE}Configuring kubectl...${NC}"
    
    # Update kubeconfig
    aws eks update-kubeconfig --region $AWS_REGION --name $EKS_CLUSTER_NAME
    print_status "kubectl configured for EKS cluster"
    
    # Verify connection
    if kubectl get nodes &> /dev/null; then
        print_status "Successfully connected to Kubernetes cluster"
    else
        print_error "Failed to connect to Kubernetes cluster"
        exit 1
    fi
}

# Function to deploy Kubernetes manifests
deploy_kubernetes() {
    echo -e "\n${BLUE}Deploying Kubernetes manifests...${NC}"
    
    # Create monitoring namespace
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    print_status "Monitoring namespace created"
    
    # Deploy monitoring stack
    kubectl apply -f monitoring/
    print_status "Monitoring stack deployed"
    
    # Wait for monitoring to be ready
    kubectl wait --for=condition=ready pod -l app=prometheus -n monitoring --timeout=300s
    
    # Update secrets with actual RDS endpoint
    kubectl create secret generic cloudapp-secrets \
        --from-literal=DB_HOST="$RDS_ENDPOINT" \
        --from-literal=DB_PASSWORD="$(cd terraform && terraform output -raw rds_password)" \
        --namespace=cloudapp \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Deploy application
    kubectl apply -f k8s/
    print_status "Application manifests deployed"
    
    # Wait for deployment to be ready
    kubectl wait --for=condition=available deployment/cloudapp-deployment -n cloudapp --timeout=300s
    print_status "Application deployment is ready"
}

# Function to install AWS Load Balancer Controller
install_alb_controller() {
    echo -e "\n${BLUE}Installing AWS Load Balancer Controller...${NC}"
    
    # Create IAM OIDC provider if it doesn't exist
    eksctl utils associate-iam-oidc-provider --cluster=$EKS_CLUSTER_NAME --approve || true
    
    # Download IAM policy
    curl -o iam_policy.json https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v2.6.0/docs/install/iam_policy.json
    
    # Create IAM policy
    aws iam create-policy \
        --policy-name AWSLoadBalancerControllerIAMPolicy \
        --policy-document file://iam_policy.json || true
    
    # Create IAM role and service account
    eksctl create iamserviceaccount \
        --cluster=$EKS_CLUSTER_NAME \
        --namespace=kube-system \
        --name=aws-load-balancer-controller \
        --role-name=AmazonEKSLoadBalancerControllerRole \
        --attach-policy-arn=arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/AWSLoadBalancerControllerIAMPolicy \
        --approve || true
    
    # Install cert-manager
    kubectl apply --validate=false -f https://github.com/jetstack/cert-manager/releases/download/v1.13.0/cert-manager.yaml
    
    # Install AWS Load Balancer Controller
    helm repo add eks https://aws.github.io/eks-charts
    helm repo update
    helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
        -n kube-system \
        --set clusterName=$EKS_CLUSTER_NAME \
        --set serviceAccount.create=false \
        --set serviceAccount.name=aws-load-balancer-controller || true
    
    print_status "AWS Load Balancer Controller installed"
    
    # Clean up
    rm -f iam_policy.json
}

# Function to run smoke tests
run_smoke_tests() {
    echo -e "\n${BLUE}Running smoke tests...${NC}"
    
    # Get service endpoint
    ENDPOINT=$(kubectl get ingress cloudapp-ingress -n cloudapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    
    if [[ -z "$ENDPOINT" ]]; then
        # Fallback to LoadBalancer service
        ENDPOINT=$(kubectl get service cloudapp-service -n cloudapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "localhost")
    fi
    
    if [[ "$ENDPOINT" != "localhost" ]]; then
        # Wait for endpoint to be accessible
        echo "Waiting for endpoint to be accessible: $ENDPOINT"
        for i in {1..30}; do
            if curl -s -o /dev/null -w "%{http_code}" http://$ENDPOINT/health | grep -q "200"; then
                print_status "Health check passed"
                break
            fi
            echo "Attempt $i/30: Waiting for endpoint..."
            sleep 10
        done
        
        # Test basic endpoints
        echo "Testing endpoints..."
        curl -s http://$ENDPOINT/health && print_status "Health endpoint works"
        curl -s http://$ENDPOINT/api/tasks && print_status "API endpoint works"
    else
        print_warning "Could not determine external endpoint. Using port-forward for testing."
        kubectl port-forward svc/cloudapp-service 8080:80 -n cloudapp &
        PORT_FORWARD_PID=$!
        sleep 5
        
        curl -s http://localhost:8080/health && print_status "Health endpoint works (via port-forward)"
        
        kill $PORT_FORWARD_PID 2>/dev/null || true
    fi
}

# Function to display access information
display_access_info() {
    echo -e "\n${GREEN}🎉 Deployment completed successfully!${NC}"
    echo "=================================================="
    
    # Application endpoints
    echo -e "\n${BLUE}📱 Application Access:${NC}"
    ALB_DNS=$(kubectl get ingress cloudapp-ingress -n cloudapp -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "Pending...")
    echo "Application URL: http://$ALB_DNS"
    echo "Health Check: http://$ALB_DNS/health"
    echo "API Docs: http://$ALB_DNS/api/tasks"
    
    # Monitoring access
    echo -e "\n${BLUE}📊 Monitoring Access:${NC}"
    echo "Prometheus: kubectl port-forward svc/prometheus 9090:9090 -n monitoring"
    echo "Grafana: kubectl port-forward svc/grafana 3000:3000 -n monitoring"
    echo "Grafana Credentials: admin / admin123"
    
    # Useful commands
    echo -e "\n${BLUE}🔧 Useful Commands:${NC}"
    echo "View pods: kubectl get pods -n cloudapp"
    echo "View HPA: kubectl get hpa -n cloudapp"
    echo "View logs: kubectl logs -f deployment/cloudapp-deployment -n cloudapp"
    echo "Scale manually: kubectl scale deployment cloudapp-deployment --replicas=5 -n cloudapp"
    
    # Load testing
    echo -e "\n${BLUE}🚀 Load Testing:${NC}"
    echo "cd load-generator"
    echo "python load_generator.py --url http://$ALB_DNS --test-type ramp --start-rps 1 --end-rps 50 --duration 300"
    echo "python demo_scenarios.py all --url http://$ALB_DNS"
}

# Main deployment flow
main() {
    echo -e "${BLUE}Starting deployment...${NC}"
    
    # Parse command line arguments
    SKIP_INFRA=false
    SKIP_BUILD=false
    
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-infra)
                SKIP_INFRA=true
                shift
                ;;
            --skip-build)
                SKIP_BUILD=true
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    check_prerequisites
    
    if [[ "$SKIP_BUILD" != "true" ]]; then
        build_and_push_image
    fi
    
    if [[ "$SKIP_INFRA" != "true" ]]; then
        deploy_infrastructure
        configure_kubectl
        install_alb_controller
    else
        # Get existing infrastructure info
        cd terraform
        EKS_CLUSTER_NAME=$(terraform output -raw eks_cluster_name)
        RDS_ENDPOINT=$(terraform output -raw rds_endpoint)
        ALB_DNS_NAME=$(terraform output -raw load_balancer_dns)
        cd ..
        configure_kubectl
    fi
    
    deploy_kubernetes
    run_smoke_tests
    display_access_info
}

# Run main function
main "$@"
