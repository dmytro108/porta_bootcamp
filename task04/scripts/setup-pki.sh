#!/bin/bash

##############################################################################
# PKI Setup Script for VPN Tunnel Lab
# 
# This script automates the complete PKI setup process:
# - Downloads and installs Easy-RSA
# - Creates Certificate Authority (CA)
# - Generates server certificate (router1)
# - Generates client certificate (router2)
# - Generates DH parameters
# - Generates TLS-auth key
# - Organizes certificates in appropriate directories
##############################################################################

set -e  # Exit on any error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
PKI_DIR="$PROJECT_DIR/pki"
CONFIGS_DIR="$PROJECT_DIR/configs"
EASYRSA_VERSION="3.1.7"
EASYRSA_URL="https://github.com/OpenVPN/easy-rsa/releases/download/v${EASYRSA_VERSION}/EasyRSA-${EASYRSA_VERSION}.tgz"

# Function to print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""
}

# Check if required commands are available
check_dependencies() {
    print_section "Checking Dependencies"
    
    local missing_deps=0
    
    if ! command -v wget &> /dev/null && ! command -v curl &> /dev/null; then
        print_error "Neither wget nor curl is installed. Please install one of them."
        missing_deps=1
    else
        print_success "Download tool available (wget or curl)"
    fi
    
    if ! command -v tar &> /dev/null; then
        print_error "tar is not installed. Please install it."
        missing_deps=1
    else
        print_success "tar is available"
    fi
    
    if ! command -v openssl &> /dev/null; then
        print_error "openssl is not installed. Please install it."
        missing_deps=1
    else
        print_success "openssl is available"
    fi
    
    if [ $missing_deps -eq 1 ]; then
        print_error "Missing required dependencies. Please install them and try again."
        exit 1
    fi
    
    print_success "All dependencies satisfied"
}

# Download and install Easy-RSA
install_easyrsa() {
    print_section "Installing Easy-RSA"
    
    cd "$PKI_DIR"
    
    if [ -d "easyrsa" ]; then
        print_warning "Easy-RSA directory already exists. Removing it..."
        rm -rf easyrsa
    fi
    
    print_info "Downloading Easy-RSA version ${EASYRSA_VERSION}..."
    
    if command -v wget &> /dev/null; then
        wget -q "${EASYRSA_URL}" -O easyrsa.tgz
    else
        curl -sL "${EASYRSA_URL}" -o easyrsa.tgz
    fi
    
    print_info "Extracting Easy-RSA..."
    tar xzf easyrsa.tgz
    mv "EasyRSA-${EASYRSA_VERSION}" easyrsa
    rm easyrsa.tgz
    
    chmod +x easyrsa/easyrsa
    
    print_success "Easy-RSA installed successfully"
}

# Initialize PKI
init_pki() {
    print_section "Initializing PKI"
    
    cd "$PKI_DIR/easyrsa"
    
    if [ -d "pki" ]; then
        print_warning "PKI directory already exists. Removing it..."
        rm -rf pki
    fi
    
    print_info "Initializing PKI structure..."
    ./easyrsa init-pki
    
    print_success "PKI initialized"
}

# Create Certificate Authority
create_ca() {
    print_section "Creating Certificate Authority"
    
    cd "$PKI_DIR/easyrsa"
    
    print_info "Building CA certificate..."
    # Use batch mode to avoid interactive prompts
    EASYRSA_BATCH=1 EASYRSA_REQ_CN="VPN-Lab-CA" ./easyrsa build-ca nopass
    
    # Verify CA creation
    if [ -f "pki/ca.crt" ] && [ -f "pki/private/ca.key" ]; then
        print_success "CA certificate created successfully"
        print_info "  CA Certificate: pki/ca.crt"
        print_info "  CA Private Key: pki/private/ca.key"
    else
        print_error "Failed to create CA certificate"
        exit 1
    fi
}

# Generate server certificate (router1)
generate_server_cert() {
    print_section "Generating Server Certificate (router1)"
    
    cd "$PKI_DIR/easyrsa"
    
    print_info "Generating server certificate for router1..."
    EASYRSA_BATCH=1 ./easyrsa build-server-full router1 nopass
    
    # Verify certificate creation
    if [ -f "pki/issued/router1.crt" ] && [ -f "pki/private/router1.key" ]; then
        print_success "Server certificate created successfully"
        print_info "  Certificate: pki/issued/router1.crt"
        print_info "  Private Key: pki/private/router1.key"
    else
        print_error "Failed to create server certificate"
        exit 1
    fi
}

# Generate client certificate (router2)
generate_client_cert() {
    print_section "Generating Client Certificate (router2)"
    
    cd "$PKI_DIR/easyrsa"
    
    print_info "Generating client certificate for router2..."
    EASYRSA_BATCH=1 ./easyrsa build-client-full router2 nopass
    
    # Verify certificate creation
    if [ -f "pki/issued/router2.crt" ] && [ -f "pki/private/router2.key" ]; then
        print_success "Client certificate created successfully"
        print_info "  Certificate: pki/issued/router2.crt"
        print_info "  Private Key: pki/private/router2.key"
    else
        print_error "Failed to create client certificate"
        exit 1
    fi
}

# Generate DH parameters
generate_dh() {
    print_section "Generating Diffie-Hellman Parameters"
    
    cd "$PKI_DIR/easyrsa"
    
    print_info "Generating DH parameters..."
    print_warning "Using 1024-bit DH for faster generation (suitable for lab/testing)"
    print_info "For production, use 2048-bit or higher"
    
    # Use 1024-bit for faster generation in lab environment
    # For production, change to 2048 or 4096
    openssl dhparam -out pki/dh.pem 1024 2>&1 | grep -v "^[.+]"
    
    # Verify DH creation
    if [ -f "pki/dh.pem" ]; then
        print_success "DH parameters generated successfully"
        print_info "  DH Parameters: pki/dh.pem (1024-bit)"
    else
        print_error "Failed to generate DH parameters"
        exit 1
    fi
}

# Generate TLS-auth key
generate_tls_auth() {
    print_section "Generating TLS-Auth Key"
    
    cd "$PKI_DIR/easyrsa"
    
    print_info "Generating TLS-auth key..."
    
    # Try openvpn first, fallback to openssl if not available
    if command -v openvpn &> /dev/null; then
        openvpn --genkey secret pki/ta.key
    else
        print_warning "OpenVPN not found, using openssl to generate TLS-auth key"
        # Generate a 2048-bit (256 byte) random key compatible with OpenVPN
        openssl rand -hex 256 > pki/ta.key
    fi
    
    # Verify TLS-auth key creation
    if [ -f "pki/ta.key" ]; then
        print_success "TLS-auth key generated successfully"
        print_info "  TLS-Auth Key: pki/ta.key"
    else
        print_error "Failed to generate TLS-auth key"
        exit 1
    fi
}

# Organize certificates for router1
organize_router1_files() {
    print_section "Organizing Files for Router1"
    
    local DEST_DIR="$CONFIGS_DIR/router1/openvpn"
    
    print_info "Copying files to $DEST_DIR..."
    
    # Copy CA certificate
    cp "$PKI_DIR/easyrsa/pki/ca.crt" "$DEST_DIR/ca.crt"
    chmod 644 "$DEST_DIR/ca.crt"
    
    # Copy server certificate
    cp "$PKI_DIR/easyrsa/pki/issued/router1.crt" "$DEST_DIR/router1.crt"
    chmod 644 "$DEST_DIR/router1.crt"
    
    # Copy server private key
    cp "$PKI_DIR/easyrsa/pki/private/router1.key" "$DEST_DIR/router1.key"
    chmod 600 "$DEST_DIR/router1.key"
    
    # Copy DH parameters
    cp "$PKI_DIR/easyrsa/pki/dh.pem" "$DEST_DIR/dh.pem"
    chmod 644 "$DEST_DIR/dh.pem"
    
    # Copy TLS-auth key
    cp "$PKI_DIR/easyrsa/pki/ta.key" "$DEST_DIR/ta.key"
    chmod 600 "$DEST_DIR/ta.key"
    
    print_success "Router1 files organized"
    print_info "  Files copied to: $DEST_DIR"
    print_info "    - ca.crt (644)"
    print_info "    - router1.crt (644)"
    print_info "    - router1.key (600)"
    print_info "    - dh.pem (644)"
    print_info "    - ta.key (600)"
}

# Organize certificates for router2
organize_router2_files() {
    print_section "Organizing Files for Router2"
    
    local DEST_DIR="$CONFIGS_DIR/router2/openvpn"
    
    print_info "Copying files to $DEST_DIR..."
    
    # Copy CA certificate
    cp "$PKI_DIR/easyrsa/pki/ca.crt" "$DEST_DIR/ca.crt"
    chmod 644 "$DEST_DIR/ca.crt"
    
    # Copy client certificate
    cp "$PKI_DIR/easyrsa/pki/issued/router2.crt" "$DEST_DIR/router2.crt"
    chmod 644 "$DEST_DIR/router2.crt"
    
    # Copy client private key
    cp "$PKI_DIR/easyrsa/pki/private/router2.key" "$DEST_DIR/router2.key"
    chmod 600 "$DEST_DIR/router2.key"
    
    # Copy TLS-auth key
    cp "$PKI_DIR/easyrsa/pki/ta.key" "$DEST_DIR/ta.key"
    chmod 600 "$DEST_DIR/ta.key"
    
    print_success "Router2 files organized"
    print_info "  Files copied to: $DEST_DIR"
    print_info "    - ca.crt (644)"
    print_info "    - router2.crt (644)"
    print_info "    - router2.key (600)"
    print_info "    - ta.key (600)"
}

# Archive PKI for backup
archive_pki() {
    print_section "Creating PKI Backup"
    
    cd "$PKI_DIR"
    
    print_info "Creating backup archive..."
    tar czf pki-backup-$(date +%Y%m%d-%H%M%S).tar.gz easyrsa/pki
    
    print_success "PKI backup created"
}

# Display summary
display_summary() {
    print_section "PKI Setup Complete"
    
    echo "The following components have been created:"
    echo ""
    echo "  ✓ Certificate Authority (CA)"
    echo "  ✓ Router1 Server Certificate"
    echo "  ✓ Router2 Client Certificate"
    echo "  ✓ Diffie-Hellman Parameters"
    echo "  ✓ TLS-Auth Key"
    echo ""
    echo "Files organized in:"
    echo "  • $CONFIGS_DIR/router1/openvpn/"
    echo "  • $CONFIGS_DIR/router2/openvpn/"
    echo ""
    echo "PKI source files located in:"
    echo "  • $PKI_DIR/easyrsa/pki/"
    echo ""
    echo -e "${GREEN}Ready for Phase 3: Docker Infrastructure${NC}"
    echo ""
}

# Main execution
main() {
    print_section "VPN Tunnel Lab - PKI Setup"
    
    print_info "Project Directory: $PROJECT_DIR"
    print_info "PKI Directory: $PKI_DIR"
    print_info "Configs Directory: $CONFIGS_DIR"
    
    # Execute all steps
    check_dependencies
    install_easyrsa
    init_pki
    create_ca
    generate_server_cert
    generate_client_cert
    generate_dh
    generate_tls_auth
    organize_router1_files
    organize_router2_files
    archive_pki
    display_summary
    
    print_success "All tasks completed successfully!"
}

# Run main function
main "$@"
