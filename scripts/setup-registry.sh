#!/bin/bash
set -e

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

echo -e "${PURPLE}🚀 CloudApp Container Registry Setup${NC}"
echo "====================================="
echo ""
echo "Choose your container registry option:"
echo ""
echo -e "${BLUE}1.${NC} AWS ECR (Elastic Container Registry) - ${GREEN}Recommended for AWS deployments${NC}"
echo "   ✅ Integrated with AWS IAM"
echo "   ✅ Private by default"
echo "   ✅ Built-in vulnerability scanning"
echo "   ✅ No rate limits"
echo ""
echo -e "${BLUE}2.${NC} Docker Hub - ${YELLOW}Good for public projects or testing${NC}"
echo "   ✅ Free public repositories"
echo "   ✅ Easy to use"
echo "   ⚠️  Rate limits for free accounts"
echo "   ⚠️  Public by default"
echo ""
echo -e "${BLUE}3.${NC} Local deployment only (no registry) - ${YELLOW}For local testing${NC}"
echo "   ✅ No external dependencies"
echo "   ⚠️  Limited to single-node clusters"
echo "   ⚠️  Images not shared across nodes"
echo ""

read -p "Enter your choice (1, 2, or 3): " choice

case $choice in
    1)
        echo -e "\n${GREEN}🐳 Setting up AWS ECR...${NC}"
        ./scripts/setup-ecr.sh
        ;;
    2)
        echo -e "\n${GREEN}🐳 Setting up Docker Hub...${NC}"
        ./scripts/setup-dockerhub.sh
        ;;
    3)
        echo -e "\n${GREEN}🐳 Setting up for local deployment...${NC}"
        ./scripts/setup-local.sh
        ;;
    *)
        echo -e "${RED}❌ Invalid choice. Please run the script again and choose 1, 2, or 3.${NC}"
        exit 1
        ;;
esac

echo -e "\n${GREEN}✅ Registry setup completed!${NC}"
echo -e "${BLUE}You can now proceed with deployment using:${NC} ./scripts/deploy.sh"
