#!/bin/bash

# OverlayIOSTOOL Build & Install Script for Dopamine
# This script builds the tweak and companion app, then installs it to a jailbroken iOS device.

set -e

echo "=========================================="
echo "OverlayIOSTOOL - Build & Install Script"
echo "=========================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if THEOS environment is set
if [ -z "$THEOS" ]; then
    echo -e "${RED}Error: THEOS environment variable is not set${NC}"
    echo "Please set THEOS to your Theos installation directory"
    echo "Example: export THEOS=/path/to/theos"
    exit 1
fi

echo -e "${GREEN}✓ THEOS found at: $THEOS${NC}"
echo ""

# Step 1: Clean previous builds
echo -e "${YELLOW}[1/4] Cleaning previous builds...${NC}"
make clean || true
rm -rf packages/* || true
echo -e "${GREEN}✓ Clean complete${NC}"
echo ""

# Step 2: Build the tweak and app
echo -e "${YELLOW}[2/4] Building tweak and companion app...${NC}"
make package FINALPACKAGE=1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful${NC}"
else
    echo -e "${RED}✗ Build failed!${NC}"
    exit 1
fi
echo ""

# Step 3: Install to device
echo -e "${YELLOW}[3/4] Installing to device...${NC}"

if [ -z "$THEOS_DEVICE_IP" ]; then
    echo "Device IP not set. Please enter your iPhone's IP address:"
    read -p "iPhone IP: " DEVICE_IP
    export THEOS_DEVICE_IP=$DEVICE_IP
else
    echo "Using device IP: $THEOS_DEVICE_IP"
fi

make install
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Installation successful${NC}"
else
    echo -e "${RED}✗ Installation failed!${NC}"
    exit 1
fi
echo ""

# Step 4: Done
echo -e "${YELLOW}[4/4] Complete${NC}"
echo ""
echo -e "${GREEN}=========================================="
echo "OverlayIOSTOOL successfully installed!"
echo "==========================================${NC}"
echo ""
echo "📱 Device will respring automatically"
echo "📲 Launch 'OverlayToolApp' from your home screen to configure"
echo ""
