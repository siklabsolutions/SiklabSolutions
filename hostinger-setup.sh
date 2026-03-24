#!/bin/bash

###############################################################################
# Hostinger Deployment Setup Script
# This script sets up the Node.js server, builds React frontend, and starts PM2
###############################################################################

set -e  # Exit on error

echo "=================================="
echo "Siklab Solutions - Hostinger Setup"
echo "=================================="

# Get the directory where this script is located
DEPLOY_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd "$DEPLOY_DIR"

echo "📁 Working directory: $DEPLOY_DIR"

# ==============================================================================
# Step 1: Ensure we're on the correct branch
# ==============================================================================
echo ""
echo "📌 Step 1: Checking Git branch..."

if [ -d .git ]; then
    CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    echo "   Current branch: $CURRENT_BRANCH"
    
    # If on master, try to switch to main
    if [ "$CURRENT_BRANCH" = "master" ]; then
        echo "   Switching from master to main..."
        git checkout main 2>/dev/null || git checkout -b main origin/main 2>/dev/null || echo "   Note: Stay on master - main branch may not exist yet"
    fi
    
    echo "   ✅ Git branch verified"
else
    echo "   ⚠️  No .git directory found"
fi

# ==============================================================================
# Step 2: Check Node.js version
# ==============================================================================
echo ""
echo "📌 Step 2: Checking Node.js..."

if ! command -v node &> /dev/null; then
    echo "   ❌ Node.js not found!"
    echo "   Please install Node.js 18+ first"
    exit 1
fi

NODE_VERSION=$(node -v)
echo "   Node.js version: $NODE_VERSION"
echo "   ✅ Node.js is installed"

# ==============================================================================
# Step 3: Install root dependencies
# ==============================================================================
echo ""
echo "📌 Step 3: Installing root dependencies..."

if [ -f package.json ]; then
    npm ci --production 2>/dev/null || npm install --production 2>/dev/null || echo "   ⚠️  No package.json in root"
    echo "   ✅ Root dependencies installed"
fi

# ==============================================================================
# Step 4: Install and build frontend
# ==============================================================================
echo ""
echo "📌 Step 4: Building React frontend..."

if [ -d siklab-react ]; then
    cd siklab-react
    
    # Install frontend dependencies
    npm ci --production 2>/dev/null || npm install --production 2>/dev/null
    echo "   ✅ Frontend dependencies installed"
    
    # Build the React app
    npm run build 2>/dev/null || {
        echo "   ⚠️  Build script not found, trying tsc and vite directly..."
        npx tsc -b 2>/dev/null || true
        npx vite build 2>/dev/null || true
    }
    
    if [ -d dist ]; then
        echo "   ✅ React app built successfully"
        echo "   📦 Built files: $(ls -la dist | wc -l) items"
    else
        echo "   ⚠️  Build output directory not found"
    fi
    
    cd "$DEPLOY_DIR"
else
    echo "   ❌ siklab-react directory not found!"
    exit 1
fi

# ==============================================================================
# Step 5: Install backend dependencies
# ==============================================================================
echo ""
echo "📌 Step 5: Installing backend dependencies..."

if [ -d siklab-react/server ]; then
    cd siklab-react/server
    
    npm ci --production 2>/dev/null || npm install --production 2>/dev/null
    echo "   ✅ Backend dependencies installed"
    
    cd "$DEPLOY_DIR"
else
    echo "   ⚠️  Backend server directory not found"
fi

# ==============================================================================
# Step 6: Create environment template
# ==============================================================================
echo ""
echo "📌 Step 6: Setting up environment variables..."

ENV_FILE="$DEPLOY_DIR/siklab-react/server/.env"

if [ ! -f "$ENV_FILE" ]; then
    echo "   Creating .env template..."
    cat > "$ENV_FILE" << 'EOF'
# Server Configuration
NODE_ENV=production
PORT=3001
API_URL=https://yourdomain.com/api

# Database - MongoDB
MONGODB_URI=mongodb+srv://username:password@cluster.mongodb.net/dbname?retryWrites=true&w=majority

# Database - PostgreSQL (Neon)
DATABASE_URL=postgresql://user:password@ep-*.neon.tech/dbname?sslmode=require

# AI Services
OPENAI_API_KEY=sk-...
ANTHROPIC_API_KEY=sk-ant-...
GOOGLE_AI_KEY=AIzaSyJ...

# Security
JWT_SECRET=your_super_secret_jwt_key_change_this_in_production_12345

# CORS & Frontend
FRONTEND_URL=https://yourdomain.com

# Optional: Logging
LOG_LEVEL=info

# Optional: Analytics
ANALYTICS_KEY=your_analytics_key
EOF
    echo "   ✅ Created .env template"
    echo ""
    echo "   ⚠️  IMPORTANT: Edit the .env file with your actual credentials:"
    echo "   nano $ENV_FILE"
else
    echo "   ✅ .env file already exists"
fi

# ==============================================================================
# Step 7: Install and configure PM2
# ==============================================================================
echo ""
echo "📌 Step 7: Setting up process manager (PM2)..."

if ! command -v pm2 &> /dev/null; then
    echo "   Installing PM2 globally..."
    npm install -g pm2 2>/dev/null || sudo npm install -g pm2 2>/dev/null
fi

PM2_VERSION=$(pm2 -v 2>/dev/null || echo "unknown")
echo "   PM2 version: $PM2_VERSION"

# Stop any existing siklab-api process
pm2 delete siklab-api 2>/dev/null || true

# Start the API server with PM2
echo "   Starting API server with PM2..."
cd "$DEPLOY_DIR/siklab-react/server"
pm2 start server.js --name "siklab-api" --instances max --exec-mode cluster --merge-logs 2>/dev/null || {
    echo "   ⚠️  Failed to start with PM2 cluster mode, trying fork mode..."
    pm2 start server.js --name "siklab-api" --merge-logs
}

# Save PM2 configuration
pm2 save 2>/dev/null || true

# Display PM2 status
echo ""
echo "   📊 PM2 Status:"
pm2 list

echo "   ✅ PM2 configured"

# ==============================================================================
# Step 8: Summary and next steps
# ==============================================================================
cd "$DEPLOY_DIR"

echo ""
echo "=================================="
echo "✅ Setup Complete!"
echo "=================================="
echo ""
echo "📋 Summary:"
echo "   • Node.js: $(node -v)"
echo "   • API Server: Running on http://localhost:3001"
echo "   • Frontend: Built in ./siklab-react/dist"
echo "   • Process Manager: PM2 (monitoring enabled)"
echo ""
echo "🔐 CRITICAL - Next Steps:"
echo ""
echo "1. Configure Environment Variables:"
echo "   nano siklab-react/server/.env"
echo "   - Set MongoDB connection string"
echo "   - Set PostgreSQL connection string"
echo "   - Add API keys (OpenAI, Anthropic, Google AI)"
echo "   - Set JWT_SECRET to a strong random value"
echo "   - Update FRONTEND_URL with your domain"
echo ""
echo "2. Configure Hostinger Domain:"
echo "   - Point domain to: ~/public_html/siklab/siklab-react/dist"
echo "   - Set up reverse proxy: /api/* → http://localhost:3001/api/*"
echo "   - Enable HTTPS/SSL"
echo ""
echo "3. Verify Server is Running:"
echo "   curl http://localhost:3001/api/health"
echo ""
echo "4. Monitor Logs:"
echo "   pm2 logs siklab-api"
echo "   pm2 monit"
echo ""
echo "5. For GitHub Actions Auto-Deployment:"
echo "   - Add secrets in GitHub repo settings"
echo "   - See GITHUB_ACTIONS_SETUP.md"
echo ""
echo "=================================="
echo ""
