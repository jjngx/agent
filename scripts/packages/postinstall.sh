#!/bin/sh

# Determine OS platform
# shellcheck source=/dev/null
. /etc/os-release


AGENT_EXE="/usr/bin/nginx-agent"
AGENT_RUN_DIR="/var/run/nginx-agent"
AGENT_LOG_DIR="/var/log/nginx-agent"
AGENT_ETC_DIR="/etc/nginx-agent"
AGENT_LIB_DIR="/var/lib/nginx-agent/"
AGENT_UNIT_LOCATION="/etc/systemd/system"
AGENT_UNIT_FILE="nginx-agent.service"
AGENT_USER=$(id -nu)
WORKER_USER=""
AGENT_GROUP="nginx-agent"

detect_nginx_users() {
    if command -V systemctl >/dev/null 2>&1; then
        printf "PostInstall: Reading NGINX systemctl unit file for user information\n"
        nginx_unit_file=$(systemctl status nginx | grep -Po "\(\K\/.*service")
        pid_file=$(grep -Po "PIDFile=\K.*$" "${nginx_unit_file}")

        if [ ! -f "$pid_file" ]; then
            printf "%s does not exist\n" "${pid_file}"
        else
            pidId=$(cat "${pid_file}")
            nginx_user=$(ps --no-headers -u -p "${pidId}" | head -1 | awk '{print $1}')
        fi

        if [ ! "${nginx_user}" ]; then
            printf "No NGINX user found\n"
        fi
    fi

    if [ -z "${nginx_user}" ]; then
        printf "PostInstall: Reading NGINX process information to determine NGINX user\n"
        nginx_user=$(ps aux | grep "nginx: master process" | grep -v grep | head -1 | awk '{print $1}')

        if [ -z "${nginx_user}" ]; then
            printf "No NGINX user found\n"
        fi
    fi

    if [ "${nginx_user}" ]; then
        echo "NGINX processes running as user '${nginx_user}'. nginx-agent will be configured to run as same user"
        AGENT_USER=${nginx_user}
    else
        echo "WARNING: No NGINX processes detected."
    fi

    if [ -z "${worker_user}" ]; then
        printf "PostInstall: Reading NGINX process information to determine NGINX user\n"
        worker_user=$(ps aux | grep "nginx: worker process" | grep -v grep | head -1 | awk '{print $1}')

        if [ -z "${worker_user}" ]; then
            printf "No NGINX worker user found\n"
        fi
    fi

    if [ "${worker_user}" ]; then
        echo "NGINX processes running as user '${worker_user}'. nginx-agent will try add that user to '${AGENT_GROUP}'"
        WORKER_USER=${worker_user}
    else
        echo "WARNING: No NGINX worker processes detected."
    fi

    if [ -z "${AGENT_USER}" ]; then
        echo "\$USER not defined. Running as root"
        USER=root
        AGENT_USER=root
    fi
}

ensure_sudo() {
    if [ "$(id -u)" = "0" ]; then
        echo "Sudo permissions detected"
    else
        echo "No sudo permission detected, please run as sudo"
        exit 1
    fi
}

ensure_agent_path() {
    if [ ! -f "${AGENT_EXE}" ]; then
        echo "nginx-agent not in default path, exiting..."
        exit 1
    fi

    printf "Found nginx-agent %s\n" "${AGENT_EXE}"
}

create_agent_group() {
    if command -V systemctl >/dev/null 2>&1; then
        printf "PostInstall: Adding nginx-agent group %s\n" "${AGENT_GROUP}"
        groupadd "${AGENT_GROUP}"

        printf "PostInstall: Adding NGINX / agent user %s to group %s\n" "${AGENT_USER}" "${AGENT_GROUP}"
        usermod -a -G "${AGENT_GROUP}" "${AGENT_USER}"
        if [ "${WORKER_USER}" ]; then
            printf "PostInstall: Adding NGINX Worker user %s to group %s\n" "${WORKER_USER}" "${AGENT_GROUP}"
            usermod -a -G "${AGENT_GROUP}" "${WORKER_USER}"
        fi
    fi

    if [ "$ID" = "alpine" ]; then
        printf "PostInstall: Adding nginx-agent group %s\n" "${AGENT_GROUP}"
        addgroup "${AGENT_GROUP}"

        printf "PostInstall: Adding NGINX / agent user %s to group %s\n" "${AGENT_USER}" "${AGENT_GROUP}"
        addgroup "${AGENT_USER}" "${AGENT_GROUP}"
        if [ "${WORKER_USER}" ]; then
            printf "PostInstall: Adding NGINX Worker user %s to group %s\n" "${WORKER_USER}" "${AGENT_GROUP}"
            addgroup "${WORKER_USER}" "${AGENT_GROUP}"
        fi
    fi
}

create_run_dir() {
    printf "PostInstall: Creating NGINX Agent run directory \n"
    mkdir -p "${AGENT_RUN_DIR}"

    printf "PostInstall: Modifying group ownership of NGINX Agent run directory \n"
    chown "${AGENT_USER}":"${AGENT_GROUP}" "${AGENT_RUN_DIR}"
}

update_user_groups() {
    printf "PostInstall: Modifying group ownership of NGINX Agent directories \n"
    chown -R "${AGENT_USER}":"${AGENT_GROUP}" "${AGENT_LOG_DIR}" "${AGENT_ETC_DIR}" "${AGENT_LIB_DIR}"
}

update_unit_file() {
    # Fill in data to unit file that's acquired post install
    if command -V systemctl >/dev/null 2>&1; then
        printf "PostInstall: Modifying NGINX Agent unit file with correct locations and user information\n"
        EXE_CMD="s|\${AGENT_EXE}|${AGENT_EXE}|g"
        sed -i -e $EXE_CMD ${AGENT_UNIT_LOCATION}/${AGENT_UNIT_FILE}

        LOG_DIR_CMD="s|\${AGENT_LOG_DIR}|${AGENT_LOG_DIR}|g"
        sed -i -e $LOG_DIR_CMD ${AGENT_UNIT_LOCATION}/${AGENT_UNIT_FILE}

        RUN_DIR_CMD="s|\${AGENT_RUN_DIR}|${AGENT_RUN_DIR}|g"
        sed -i -e $RUN_DIR_CMD ${AGENT_UNIT_LOCATION}/${AGENT_UNIT_FILE}

        USER_CMD="s/\${AGENT_USER}/${AGENT_USER}/g"
        sed -i -e $USER_CMD ${AGENT_UNIT_LOCATION}/${AGENT_UNIT_FILE}

        GROUP_CMD="s/\${AGENT_GROUP}/${AGENT_GROUP}/g"
        sed -i -e $GROUP_CMD ${AGENT_UNIT_LOCATION}/${AGENT_UNIT_FILE}

        printf "PostInstall: Reload the service unit from disk\n"
        systemctl daemon-reload
        printf "PostInstall: Unmask the service unit from disk\n"
        systemctl unmask "${AGENT_UNIT_FILE}"
        printf "PostInstall: Set the preset flag for the service unit\n"
        systemctl preset "${AGENT_UNIT_FILE}"
        printf "PostInstall: Set the enabled flag for the service unit\n"
        systemctl enable "${AGENT_UNIT_FILE}"
    fi
}

restart_agent_if_required() {
    if service nginx-agent status >/dev/null 2>&1; then
        printf "PostInstall: Restarting nginx agent\n"
        service nginx-agent restart || true
    fi
}

summary() {
    echo "----------------------------------------------------------------------"
    echo " NGINX Agent package has been successfully installed."
    echo ""
    echo " Please follow the next steps to start the software:"
    echo "    sudo systemctl start nginx-agent"
    echo ""
    echo " Configuration settings can be adjusted here:"
    echo "    /etc/nginx-agent/nginx-agent.conf"
    echo ""
    echo "----------------------------------------------------------------------"
}

#
# Main body of the script
#
{
    detect_nginx_users
    ensure_sudo
    ensure_agent_path
    create_agent_group
    create_run_dir
    update_user_groups
    update_unit_file
    restart_agent_if_required
    summary
}
