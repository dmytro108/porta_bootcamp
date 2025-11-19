#!/bin/bash

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

TARGET_USER="$1"
TARGET_UID="$2"
TARGET_GID="$3"

if [ -z "$TARGET_USER" ] || [ -z "$TARGET_UID" ] || [ -z "$TARGET_GID" ]; then
    echo -e "${RED}Usage: $0 <username> <uid> <gid>${NC}" >&2
    exit 1
fi

find_free_uid() {
    local start_uid="$1"
    local candidate_uid="$start_uid"

    while getent passwd "${candidate_uid}" >/dev/null; do
        candidate_uid=$((candidate_uid + 1))
    done

    echo "${candidate_uid}"
}

find_free_gid() {
    local start_gid="$1"
    local candidate_gid="$start_gid"

    while getent group "${candidate_gid}" >/dev/null; do
        candidate_gid=$((candidate_gid + 1))
    done

    echo "${candidate_gid}"
}

remap_uid() {
    local old_uid="$1"
    local new_uid="$2"
    local user

    user="$(getent passwd "${old_uid}" | cut -d: -f1 || true)"
    if [ -z "${user}" ]; then
        return 0
    fi

    echo -e "${YELLOW}Remapping UID ${old_uid} for user ${user} to ${new_uid}...${NC}"
    sudo usermod -u "${new_uid}" "${user}"

    echo -e "${YELLOW}\tUpdating file ownership from UID ${old_uid} to ${new_uid} (this may take a while)...${NC}"
    sudo find / -xdev -uid "${old_uid}" -exec chown -h "${new_uid}" {} + 2>/dev/null || true

    echo -e "${GREEN}\tUID remap completed for user ${user}${NC}"
}

remap_gid() {
    local old_gid="$1"
    local new_gid="$2"
    local group

    group="$(getent group "${old_gid}" | cut -d: -f1 || true)"
    if [ -z "${group}" ]; then
        return 0
    fi

    echo -e "${YELLOW}Remapping GID ${old_gid} for group ${group} to ${new_gid}...${NC}"
    sudo groupmod -g "${new_gid}" "${group}"

    echo -e "${YELLOW}\tUpdating file group ownership from GID ${old_gid} to ${new_gid} (this may take a while)...${NC}"
    sudo find / -xdev -gid "${old_gid}" -exec chgrp -h "${new_gid}" {} + 2>/dev/null || true

    echo -e "${GREEN}\tGID remap completed for group ${group}${NC}"
}

ensure_user_and_group() {
    local username="$1"
    local uid="$2"
    local gid="$3"

    # Ensure group exists with given GID
    local existing_group_by_gid existing_group_by_name new_gid

    existing_group_by_gid="$(getent group "${gid}" | cut -d: -f1 || true)"
    existing_group_by_name="$(getent group "${username}" | cut -d: -f3 || true)"

    if [ -n "${existing_group_by_gid}" ] && [ "${existing_group_by_gid}" != "${username}" ]; then
        new_gid="$(find_free_gid $((gid + 1)))"
        remap_gid "${gid}" "${new_gid}"
    fi

    if ! getent group "${username}" >/dev/null; then
        echo -e "${YELLOW}Creating group ${username} with GID ${gid}...${NC}"
        sudo groupadd -g "${gid}" "${username}"
    else
        if [ "${existing_group_by_name}" != "${gid}" ]; then
            echo -e "${YELLOW}Updating group ${username} GID to ${gid}...${NC}"
            sudo groupmod -g "${gid}" "${username}"
        fi
    fi

    # Ensure user exists with given UID/GID
    local existing_user_by_name existing_user_uid existing_user_gid existing_user_by_uid new_uid

    existing_user_by_name="$(getent passwd "${username}" | cut -d: -f1 || true)"
    existing_user_uid="$(getent passwd "${username}" | cut -d: -f3 || true)"
    existing_user_gid="$(getent passwd "${username}" | cut -d: -f4 || true)"
    existing_user_by_uid="$(getent passwd "${uid}" | cut -d: -f1 || true)"

    if [ -z "${existing_user_by_name}" ]; then
        if [ -n "${existing_user_by_uid}" ]; then
            new_uid="$(find_free_uid $((uid + 1)))"
            remap_uid "${uid}" "${new_uid}"
        fi

        echo -e "${YELLOW}Creating user ${username} with UID ${uid} and GID ${gid}...${NC}"
        sudo useradd -u "${uid}" -g "${gid}" -m "${username}"
        return 0
    fi

    # User exists but may have different UID/GID
    if [ "${existing_user_uid}" != "${uid}" ]; then
        if [ -n "${existing_user_by_uid}" ] && [ "${existing_user_by_uid}" != "${username}" ]; then
            new_uid="$(find_free_uid $((uid + 1)))"
            remap_uid "${uid}" "${new_uid}"
        fi

        echo -e "${YELLOW}Updating user ${username} UID to ${uid}...${NC}"
        sudo usermod -u "${uid}" "${username}"
        echo -e "${YELLOW}\tUpdating file ownership from UID ${existing_user_uid} to ${uid} (this may take a while)...${NC}"
        sudo find / -xdev -uid "${existing_user_uid}" -exec chown -h "${uid}" {} + 2>/dev/null || true
    fi

    if [ "${existing_user_gid}" != "${gid}" ]; then
        echo -e "${YELLOW}Updating user ${username} GID to ${gid}...${NC}"
        sudo usermod -g "${gid}" "${username}"
        echo -e "${YELLOW}\tUpdating file group ownership from GID ${existing_user_gid} to ${gid} (this may take a while)...${NC}"
        sudo find / -xdev -gid "${existing_user_gid}" -exec chgrp -h "${gid}" {} + 2>/dev/null || true
    fi
}

ensure_user_and_group "${TARGET_USER}" "${TARGET_UID}" "${TARGET_GID}"
