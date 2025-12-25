#!/bin/bash

# DNS64/NAT64 configuration for IPv6-only servers
# This script configures nat64.net DNS servers to allow IPv6-only machines
# to reach IPv4-only hosts (like github.com)

# Define colors
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Print functions for readability
print_section() { printf "\n${BOLD}=== %s ===${NC}\n\n" "$1"; }
print_message() { printf "${CYAN} %s${NC}\n" "$1"; }
print_success() { printf "${GREEN} %s${NC}\n" "$1"; }
print_warning() { printf "${YELLOW} %s${NC}\n" "$1"; }
print_error() { printf "${RED} %s${NC}\n" "$1"; }
print_debug() { printf "${GRAY}  %s${NC}\n" "$1"; }

# Check if we have IPv4 connectivity
check_ipv4_connectivity() {
    print_message "Checking IPv4 connectivity..."
    if ping -c 1 -W 3 8.8.8.8 &>/dev/null; then
        print_success "IPv4 connectivity available."
        return 0
    else
        print_warning "No IPv4 connectivity detected."
        return 1
    fi
}

# Check if we have IPv6 connectivity
check_ipv6_connectivity() {
    print_message "Checking IPv6 connectivity..."
    if ping -6 -c 1 -W 3 2001:4860:4860::8888 &>/dev/null; then
        print_success "IPv6 connectivity available."
        return 0
    else
        print_error "No IPv6 connectivity detected."
        return 1
    fi
}

# Check if DNS64 is already configured
check_dns64_configured() {
    if [[ -f /etc/netplan/60-dns64.yaml ]]; then
        print_debug "DNS64 netplan config already exists."
        return 0
    fi
    return 1
}

# Configure DNS64 via netplan
configure_dns64_netplan() {
    print_message "Configuring DNS64 via netplan..."

    # Find the primary network interface
    local interface
    local route_output
    local awk_output
    route_output=$(ip -6 route show default) || true
    awk_output=$(echo "${route_output}" | awk '{print $5}') || true
    interface=$(echo "${awk_output}" | head -1)

    if [[ -z "${interface}" ]]; then
        print_error "Could not detect primary network interface."
        return 1
    fi

    print_debug "Detected interface: ${interface}"

    # Create netplan config for DNS64
    sudo tee /etc/netplan/60-dns64.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    ${interface}:
      nameservers:
        addresses:
        - 2a00:1098:2c::1
        - 2a00:1098:2b::1
        - 2a01:4f8:c2c:123f::1
EOF

    # Fix permissions
    sudo chmod 600 /etc/netplan/60-dns64.yaml

    # Apply netplan
    print_message "Applying netplan configuration..."
    if sudo netplan apply; then
        print_success "DNS64 configured successfully."
    else
        print_error "Failed to apply netplan configuration."
        return 1
    fi
}

# Test that DNS64 is working
test_dns64() {
    print_message "Testing DNS64 configuration..."

    # Wait for DNS to settle
    sleep 2

    # Test resolving an IPv4-only host
    if curl -s --max-time 10 https://github.com/scowalt.keys > /dev/null 2>&1; then
        print_success "DNS64/NAT64 is working - can reach IPv4-only hosts."
        return 0
    else
        print_error "DNS64/NAT64 test failed - cannot reach IPv4-only hosts."
        return 1
    fi
}

# Main
main() {
    print_section "DNS64/NAT64 Configuration for IPv6-only Servers"

    # Check connectivity
    local has_ipv4=false

    if check_ipv4_connectivity; then
        has_ipv4=true
    fi

    if ! check_ipv6_connectivity; then
        print_error "This machine has no IPv6 connectivity. DNS64 requires IPv6."
        exit 1
    fi

    # If we have IPv4, DNS64 is not needed
    if [[ "${has_ipv4}" == "true" ]]; then
        print_success "Machine has IPv4 connectivity. DNS64 is not required."
        exit 0
    fi

    print_section "Configuring DNS64 for IPv6-only Network"

    # Check if already configured
    if check_dns64_configured; then
        print_message "DNS64 already configured. Verifying..."
        if test_dns64; then
            print_success "DNS64 is already configured and working."
            exit 0
        else
            print_warning "DNS64 config exists but not working. Reconfiguring..."
        fi
    fi

    # Configure DNS64
    if ! configure_dns64_netplan; then
        print_error "Failed to configure DNS64."
        exit 1
    fi

    # Test the configuration
    if ! test_dns64; then
        print_error "DNS64 configuration failed verification."
        exit 1
    fi

    print_section "DNS64 Configuration Complete"
    print_success "Your IPv6-only server can now reach IPv4-only hosts via NAT64."
    print_message "DNS servers configured: nat64.net"
    print_debug "  - 2a00:1098:2c::1"
    print_debug "  - 2a00:1098:2b::1"
    print_debug "  - 2a01:4f8:c2c:123f::1"
}

main "$@"
