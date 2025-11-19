#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${YELLOW}$*${NC}"
}

log_success() {
    echo -e "${GREEN}$*${NC}"
}

log_error() {
    echo -e "${RED}$*${NC}" >&2
}

usage() {
    cat <<EOF
Usage: $(basename "$0") <base_dir> <openssl_ca_conf> <csr_conf>

  base_dir        Base directory where ca/, server/, client/ will be created
  openssl_ca_conf OpenSSL CA configuration file (used for CA and signing)
  csr_conf        OpenSSL CSR configuration file (used for server/client CSRs)

All paths must be readable. Directories will be created if missing.
EOF
}

ensure_dirs() {
    local base_dir="$1"
    mkdir -p "${base_dir}/ca" "${base_dir}/server" "${base_dir}/client"
}

generate_ca() {
    local base_dir="$1"
    local ca_conf="$2"

    local ca_dir="${base_dir}/ca"
    local ca_private_dir="${ca_dir}/private"
    local ca_certs_dir="${ca_dir}/certs"
    local ca_newcerts_dir="${ca_dir}/newcerts"

    mkdir -p "${ca_private_dir}" "${ca_certs_dir}" "${ca_newcerts_dir}"
    touch "${ca_dir}/index.txt"
    if [ ! -f "${ca_dir}/serial" ]; then
        echo '1000' > "${ca_dir}/serial"
    fi

    log_info "Generating CA private key..."
    openssl genrsa -out "${ca_private_dir}/ca.key" 4096

    log_info "Generating CA self-signed certificate..."
    openssl req -new -x509 -days 3650 \
        -key "${ca_private_dir}/ca.key" \
        -out "${ca_certs_dir}/ca.crt" \
        -config "${ca_conf}" \
        -extensions v3_ca
}

generate_cert_pair() {
    local base_dir="$1"   # base directory
    local ca_conf="$2"    # CA openssl config
    local csr_conf="$3"   # CSR openssl config
    local role="$4"       # "server" or "client"

    local ca_dir="${base_dir}/ca"
    local ca_key="${ca_dir}/private/ca.key"
    local ca_cert="${ca_dir}/certs/ca.crt"
    local out_dir="${base_dir}/${role}"

    local key_file="${out_dir}/${role}.key"
    local csr_file="${out_dir}/${role}.csr"
    local crt_file="${out_dir}/${role}.crt"

    log_info "Generating ${role} private key and CSR..."
    openssl req -newkey rsa:2048 -nodes \
        -keyout "${key_file}" \
        -out "${csr_file}" \
        -config "${csr_conf}"

    # Convert to absolute paths for use in subshell
    local abs_ca_conf="$(realpath "${ca_conf}")"
    local abs_csr_file="$(realpath "${csr_file}")"
    local abs_crt_file="$(realpath -m "${crt_file}")"

    log_info "Signing ${role} certificate with CA..."
    (cd "${ca_dir}" && openssl ca -batch \
        -config "${abs_ca_conf}" \
        -keyfile "private/ca.key" \
        -cert "certs/ca.crt" \
        -in "${abs_csr_file}" \
        -out "${abs_crt_file}" \
        -extensions v3_req)

    chmod 400 "${key_file}"
}

verify_chain() {
    local ca_cert="$1"
    local key_file="$2"
    local cert_file="$3"

    log_info "Verifying that certificate matches private key..."
    openssl x509 -noout -modulus -in "${cert_file}" | openssl md5 > /tmp/cert.md5
    openssl rsa  -noout -modulus -in "${key_file}"  | openssl md5 > /tmp/key.md5
    if ! cmp -s /tmp/cert.md5 /tmp/key.md5; then
        rm -f /tmp/cert.md5 /tmp/key.md5
        log_error "Certificate and key do not match: ${cert_file}"
        exit 1
    fi
    rm -f /tmp/cert.md5 /tmp/key.md5

    log_info "Verifying certificate chain against CA..."
    openssl verify -CAfile "${ca_cert}" "${cert_file}"
}

main() {
    if [ "$#" -ne 3 ]; then
        usage
        exit 1
    fi

    local base_dir="$1"
    local ca_conf="$2"
    local csr_conf="$3"

    if [ ! -r "${ca_conf}" ]; then
        log_error "CA config not readable: ${ca_conf}"
        exit 1
    fi
    if [ ! -r "${csr_conf}" ]; then
        log_error "CSR config not readable: ${csr_conf}"
        exit 1
    fi

    ensure_dirs "${base_dir}"

    log_info "Creating CA in ${base_dir}/ca"
    generate_ca "${base_dir}" "${ca_conf}"

    log_info "Creating server certificates in ${base_dir}/server"
    generate_cert_pair "${base_dir}" "${ca_conf}" "${csr_conf}" "server"

    log_info "Creating client certificates in ${base_dir}/client"
    generate_cert_pair "${base_dir}" "${ca_conf}" "${csr_conf}" "client"

    local ca_cert="${base_dir}/ca/certs/ca.crt"
    local server_key="${base_dir}/server/server.key"
    local server_cert="${base_dir}/server/server.crt"
    local client_key="${base_dir}/client/client.key"
    local client_cert="${base_dir}/client/client.crt"

    log_info "Verifying server certificate and key with CA..."
    verify_chain "${ca_cert}" "${server_key}" "${server_cert}"

    log_info "Verifying client certificate and key with CA..."
    verify_chain "${ca_cert}" "${client_key}" "${client_cert}"

    log_success "Certificates generated and verified successfully in ${base_dir}"
}

main "$@"
