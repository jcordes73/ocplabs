#!/bin/bash

trap interrupt 1 2 3 6 9 15

function interrupt()
{
  log error "OpenShift Enterprise v3.9 installation aborted"
  exit
}

function log()
{
  DATE="`date`"
  COLOR=""
  case "$1" in
    debug)
      COLOR="" 
    ;;
    info)
      COLOR="\x1B[01;94m"
    ;;
    warn)
      COLOR="\x1B[01;93m"
    ;;
    error)
      COLOR="\x1B[31m"
    ;;
  esac

  echo -e "${COLOR}$DATE $1 $2\x1B[0m"
}

function show_input_info()
{
  echo -e -n "\x1B[01;94m$1:\x1B[0m"
}

function show_usage() {
  echo "Usage: ocplabs.sh <install|deinstall|offline-storage> <parameters>"
  echo "  Mandatory parameters"
  echo "    --root-password=<root-password>"
  echo "    --rhn-user=<rhn-user>"
  echo "    --rhn-password=<rhn-password>"
  echo "    --rhn-pool-id=<rhn-pool-id>"
  echo "    --ocp-dns=<ocp-dns-list>"
  echo "    --ocp-gateway=<ocp-gateway>"
  echo "  Optional parameters"
  echo "    --proxy=<host>:<port>"
  echo "    --proxy-user=<user>:<password>"
}

function check_variables() {
  if [ "x$ROOT_PASSWORD" = "x" ] ; then
    show_input_info "Root password"
    read -s ROOT_PASSWORD
    echo
  fi

  if [ "x$RHN_USER" = "x" ] ; then
    show_input_info "RHN user"
    read RHN_USER
    echo
  fi

  if [ "x$RHN_PASSWORD" = "x" ] ; then
    show_input_info "RHN password"
    read -s RHN_PASSWORD
    echo
  fi

  if [ "x$RHN_POOL_ID" = "x" ] ; then
    show_input_info "RHN Subscription Pool-ID"
    read RHN_POOL_ID
    echo
  fi

  if [ "x$OCP_DNS_1" = "x" ] || [ "x$OCP_DNS_2" = "x" ] ; then
    show_input_info "DNS Servers"
    read OCP_DNS
    OCP_DNS_1="`echo $OCP_DNS | cut -d',' -f1`"
    OCP_DNS_2="`echo $OCP_DNS | cut -d',' -f2`"
    echo
  fi

  if [ "x$OCP_GATEWAY" = "x" ] ; then
    show_input_info "Network Gateway"
    read OCP_GATEWAY
    echo
  fi

  if [ ! "${PROXY_HOST}x" = "x" ] ; then
    if [ ! "${PROXY_USER}x" = "x" ] ; then
      git config --global http.proxy http://${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}
      git config --global https.proxy https://${PROXY_USER}:${PROXY_PASS}@${PROXY_HOST}:${PROXY_PORT}
    else
      git config --global http.proxy http://${PROXY_HOST}:${PROXY_PORT}
      git config --global https.proxy https://${PROXY_HOST}:${PROXY_PORT}
    fi
  fi

  if [ ! "${ATOMIC_VERSION}" = "latest" ] ; then
    ATOMIC_VERSION="v${ATOMIC_VERSION}"
  fi
}

function bastion_host_preparation() {
   # Prepare hosts
  log info "Bastion Host preparation started."

  cat > ocplabs-ansible-variables.json <<EOF
{
  "ansible_connection": "ssh",
  "ansible_ssh_user": "root",
  "ansible_ssh_pass": "${ROOT_PASSWORD}",
  "rhn_user": "${RHN_USERNAME}",
  "rhn_password": "${RHN_PASSWORD}",
  "rhn_pool_id": "${RHN_POOL_ID}",
  "ocp_docker_registry_host": "${OCP_DOCKER_REGISTRY_HOST}",
  "ocp_docker_registry_port": "${OCP_DOCKER_REGISTRY_PORT}",
  "ocp_dns_1": "${OCP_DNS_1}",
  "ocp_dns_2": "${OCP_DNS_2}",
  "ocp_gateway": "${OCP_GATEWAY}"
}
EOF

  yum install -y ansible >> ocplabs.log 2>&1
  cp .ansible.cfg /etc/ansible/ansible.cfg
  ansible-playbook -vv -i ocplabs-ocp-inventory.cfg ocplabs-bastion-host-setup.yaml -e "@ocplabs-ansible-variables.json" >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Bastion Host preparation failed. Aborting."
    exit
  fi

  rm ocplabs-ansible-variables.json

  log info "Bastion Host preparation finished."
}

function ocp_nodes_preparation() {
  log info "OCP Nodes preparation started."

  cat > ocplabs-ansible-variables.json <<EOF
{
  "ansible_connection": "ssh",
  "ansible_ssh_user": "root",
  "ansible_ssh_pass": "${ROOT_PASSWORD}",
  "rhn_user": "${RHN_USERNAME}",
  "rhn_password": "${RHN_PASSWORD}",
  "rhn_pool_id": "${RHN_POOL_ID}",
  "ocp_docker_registry_host": "${OCP_DOCKER_REGISTRY_HOST}",
  "ocp_docker_registry_port": "${OCP_DOCKER_REGISTRY_PORT}",
  "ocp_dns_1": "${OCP_DNS_1}",
  "ocp_dns_2": "${OCP_DNS_2}",
  "ocp_gateway": "${OCP_GATEWAY}"
}
EOF
 
  ansible-playbook -vv -i ocplabs-ocp-inventory.cfg ocplabs-ocp-nodes-setup.yaml -e "@ocplabs-ansible-variables.json" >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "OCP Nodes preparation failed. Aborting."
    exit
  fi

  rm ocplabs-ansible-variables.json

  log info "OCP Nodes preparation finished."
}


OPTS="$*"
HOSTNAME="`hostname`"
DOMAIN="`echo $HOSTNAME | cut -d'.' -f2-`"
PROXY_HOST=""
PROXY_PORT=""
PROXY_USER=""
PROXY_PASS=""
OCP_DOCKER_REGISTRY_HOST=192.168.0.106
OCP_DOCKER_REGISTRY_PORT=5000
MODE=unknown
OFFLINE=false

for opt in $OPTS ; do
  VALUE="`echo $opt | cut -d"=" -f2`"

  case "$opt" in
    install)
      MODE=install
    ;;
    cns-install)
      MODE=cns-install
    ;;
    deinstall)
      MODE=deinstall
    ;;
    cns-deinstall)
      MODE=cns-deinstall
    ;;
    offline-storage)
      MODE=offline-storage
    ;;
    --root-password=*)
      ROOT_PASSWORD=$VALUE
    ;;
    --rhn-user=*)
      RHN_USER=$VALUE
    ;;
    --rhn-password=*)
      RHN_PASSWORD=$VALUE
    ;;
    --rhn-pool-id=*)
      RHN_POOL_ID=$VALUE
    ;;
    --ocp-dns=*)
      OCP_DNS_1="`echo $VALUE | cut -d',' -f1`"
      OCP_DNS_2="`echo $VALUE | cut -d',' -f2`"
    ;;
    --ocp-gateway=*)
      OCP_GATEWAY=$VALUE
    ;;
    --proxy=*)
      PROXY_HOST="`echo $VALUE | cut -d':' -f1`"
      PROXY_PORT="`echo $VALUE | cut -d':' -f2`"
    ;;
    --proxy-user=*)
      PROXY_USER="`echo $VALUE | cut -d':' -f1`"
      PROXY_PASS="`echo $VALUE | cut -d':' -f2`"
  esac
done

if [ ! -f "ocplabs-ocp-inventory.cfg" ] ; then
  log error "Mandatory configuration-file ocplabs-ocp-inventory.cfg missing."
  exit
fi

case "$MODE" in
  offline-storage)
  check_variables
  bastion_host_preparation
  cat > ocplabs-ansible-variables.json <<EOF
{
  "ocp_docker_registry_host": "${OCP_DOCKER_REGISTRY_HOST}",
  "ocp_docker_registry_port": "${OCP_DOCKER_REGISTRY_PORT}"
}
EOF

  ansible-playbook -vv -i ocplabs-ocp-inventory.cfg ocplabs-bastion-host-prefetch-docker-images.yaml -e "@ocplabs-ansible-variables.json" -e "@ocplabs-container-catalog-redhat-access.yaml">> ocplabs.log 2>&1
 
  ;;
  install)

  check_variables
  bastion_host_preparation
  ocp_nodes_preparation

  log info "Starting OpenShift Container Platform v3.9 installation."

  ansible-playbook -v -i ocplabs-ocp-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Prerequisites check failed. Aborting."
    exit
  fi

  ansible-playbook -v -i ocplabs-ocp-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Deployment failed. Aborting."
    exit
  fi

  log info "Post Installation started."
  ansible-playbook -vv -i ocplabs-ocp-inventory.cfg ocplabs-ocp-nodes-post-setup.yaml >> ocplabs.log 2>&1
 
  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Post Installation failed. Aborting."
    exit
  fi

  log info "Post Installation finished."
  
  log info "Finished OpenShift Container Platform v3.9 installation."
;;
cns-install)

  check_variables

  log info "Starting OpenShift Container Platform v3.9 CNS installation."

  log info "Deployment started."

  ansible-playbook -v -i ocplabs-cns-inventory.cfg ocplabs-cns-nodes-setup.yaml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "CNS Installation failed. Aborting."
    exit
  fi

  log info "Finished OpenShift Container Platform v3.9 CNS installation."
;;
deinstall)
  log info "Starting OpenShift Container Platform v3.9 deinstallation."  
  ansible-playbook -vv -i ocplabs-ocp-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/adhoc/uninstall.yml >> ocplabs.log 2>&1
  ansible-playbook -vv -i ocplabs-ocp-inventory.cfg ocplabs-ocp-nodes-deinstall.yaml >> ocplabs.log 2>&1 
  log info "Finished OpenShift Container Platform v3.9 deinstallation."
;;
cns-deinstall)
  log info "Starting OpenShift Container Platform v3.9 CNS deinstallation."
  ansible-playbook -vv -i ocplabs-cns-inventory.cfg ocplabs-cns-nodes-deinstall.yaml >> ocplabs.log 2>&1
  log info "Finished OpenShift Container Platform v3.9 CNS deinstallation."
;;
*)
  show_usage
  exit
;;
esac
