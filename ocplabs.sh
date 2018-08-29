#!/bin/bash

trap interrupt 1 2 3 6 9 15

function interrupt()
{
  log error "OpenShift Enterprise v3.10 installation aborted"
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
  echo "Usage: ocplabs.sh <install|deinstall|cns-install|cns-deinstall|offline-storage> <parameters>"
  echo "  Optional parameters"
  echo "    --proxy=<host>:<port>"
  echo "    --proxy-user=<user>:<password>"
}

function check_variables() {
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

  yum install -y ansible >> ocplabs.log 2>&1
  cp .ansible.cfg /etc/ansible/ansible.cfg
  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg ocplabs-bastion-host-setup.yaml -e "@ocplabs-ansible-variables.json" >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Bastion Host preparation failed. Aborting."
    exit
  fi

  log info "Bastion Host preparation finished."
}

function ocp_nodes_preparation() {
  log info "OCP Nodes preparation started."

  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg ocplabs-ocp-nodes-setup.yaml -e "@ocplabs-ansible-variables.json" >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "OCP Nodes preparation failed. Aborting."
    exit
  fi

  log info "OCP Nodes preparation finished."
}

function ocp_nodes_prerequisites_check() {
  log info "OCP Installation Prerequisites check started."

  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "OCP Installation Prerequisites check failed. Aborting."
    exit
  fi

  log info "OCP Installation Prerequisites check finished."
}


OPTS="$*"
HOSTNAME="`hostname`"
DOMAIN="`echo $HOSTNAME | cut -d'.' -f2-`"
PROXY_HOST=""
PROXY_PORT=""
PROXY_USER=""
PROXY_PASS=""
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

  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg ocplabs-bastion-host-prefetch-docker-images.yaml -e "@ocplabs-ansible-variables.json" -e "@ocplabs-container-catalog-redhat-access.yaml">> ocplabs.log 2>&1
 
  ;;
  install)

  check_variables
  bastion_host_preparation
  ocp_nodes_preparation
  ocp_nodes_prerequisites_check

  log info "Starting OpenShift Container Platform v3.10 installation."

  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/prerequisites.yml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Prerequisites check failed. Aborting."
    exit
  fi

  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/deploy_cluster.yml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Deployment failed. Aborting."
    exit
  fi

  log info "Post Installation started."
  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg ocplabs-ocp-nodes-post-setup.yaml >> ocplabs.log 2>&1
 
  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Post Installation failed. Aborting."
    exit
  fi

  log info "Post Installation finished."
  
  log info "Finished OpenShift Container Platform v3.10 installation."
;;
cns-install)

  check_variables

  log info "Starting OpenShift Container Platform v3.10 CNS installation."

  log info "Deployment started."

  ansible-playbook -vvv -i ocplabs-cns-inventory.cfg ocplabs-cns-nodes-setup.yaml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "CNS Installation failed. Aborting."
    exit
  fi

  log info "Finished OpenShift Container Platform v3.10 CNS installation."
;;
deinstall)
  log info "Starting OpenShift Container Platform v3.10 deinstallation."  
  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/adhoc/uninstall.yml >> ocplabs.log 2>&1
  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg ocplabs-ocp-nodes-deinstall.yaml >> ocplabs.log 2>&1 
  log info "Finished OpenShift Container Platform v3.10 deinstallation."
;;
cns-deinstall)
  log info "Starting OpenShift Container Platform v3.10 CNS deinstallation."
  ansible-playbook -vvv -i ocplabs-cns-inventory.cfg ocplabs-cns-nodes-deinstall.yaml >> ocplabs.log 2>&1
  log info "Finished OpenShift Container Platform v3.10 CNS deinstallation."
;;
*)
  show_usage
  exit
;;
esac
