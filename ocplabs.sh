#!/bin/bash

trap interrupt 1 2 3 6 9 15

function interrupt()
{
  log error "OpenShift Enterprise v3.6 installation aborted"
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

OPTS="$*"
HOSTNAME="`hostname`"
DOMAIN="`echo $HOSTNAME | cut -d'.' -f2-`"
PROXY_HOST=""
PROXY_PORT=""
PROXY_USER=""
PROXY_PASS=""
OCP_ATOMIC_VERSION=latest
OCP_DOCKER_REGISTRY=registry.access.redhat.com
MODE=unknown
OFFLINE=false
OFFLINE_HOST=192.168.0.100
OFFLINE_USER=admin
OFFLINE_PASSWORD='redhat2017!'
OFFLINE_REPO="http://${OFFLINE_HOST}/shares/U"

for opt in $OPTS ; do
  VALUE="`echo $opt | cut -d"=" -f2`"

  case "$opt" in
    install)
      MODE=install
    ;;
    deinstall)
      MODE=deinstall
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
    --offline)
      OFFLINE=true
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

if [ ! -f "ocplabs-inventory.cfg" ] ; then
  log error "Mandatory configuration-file ocplabs-inventory.cfg missing."
  exit
fi

case "$MODE" in
  offline-storage)
  cat > ocplabs-ansible-variables.json <<EOF
{
  "offline_host": "${OFFLINE_HOST}",
  "offline_user": "${OFFLINE_USER}",
  "offline_password": "${OFFLINE_PASSWORD}",
  "offline_repo": "${OFFLINE_REPO}"
}
EOF

  ansible-playbook -vv -i ocplabs-inventory.cfg ocplabs-host-prefetch-docker-images.yaml -e "@ocplabs-ansible-variables.json" -e "@ocplabs-container-catalog.yaml">> ocplabs.log 2>&1
 
  ;;
  install)

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

  log info "Starting OpenShift Container Platform v3.6 installation."

  # Prepare hosts
  log info "Hosts preparation started."

  cat > ocplabs-ansible-variables.json <<EOF
{
  "ansible_connection": "ssh",
  "ansible_ssh_user": "root",
  "ansible_ssh_pass": "${ROOT_PASSWORD}",
  "rhn_user": "${RHN_USERNAME}",
  "rhn_password": "${RHN_PASSWORD}",
  "rhn_pool_id": "${RHN_POOL_ID}",
  "ocp_docker_registry": "${OCP_DOCKER_REGISTRY}",
  "ocp_dns_1": "${OCP_DNS_1}",
  "ocp_dns_2": "${OCP_DNS_2}",
  "ocp_gateway": "${OCP_GATEWAY}",
  "offline": "${OFFLINE}",
  "offline_repo": "${OFFLINE_REPO}"
}
EOF

  ansible-playbook -vv -i ocplabs-inventory.cfg ocplabs-host-setup.yaml -e "@ocplabs-ansible-variables.json" >> ocplabs.log 2>&1 

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Host preparation failed. Aborting."
    exit
  fi

  rm ocplabs-ansible-variables.json

  log info "Hosts preparation finished."

  log info "Deployment started."

  ansible-playbook -v -i ocplabs-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/byo/config.yml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Deployment failed. Aborting."
    exit
  fi

  #oc adm policy add-role-to-user view system:serviceaccount:openshift-infra:hawkular -n openshift-infra >> ocplabs.log 2>&1

  log info "Deployment finished."

  log info "Post Installation started."
  ansible-playbook -vv -i ocplabs-inventory.cfg ocplabs-host-post-setup.yaml >> ocplabs.log 2>&1
 
  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Post Installation failed. Aborting."
    exit
  fi

  log info "Post Installation finished."
  
  log info "Finished OpenShift Container Platform 3.6 installation."
;;
deinstall)
  log info "Starting OpenShift Container Platform v3.6 deinstallation."  
  ansible-playbook -vv -i ocplabs-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/adhoc/uninstall.yml >> ocplabs.log 2>&1
  ansible-playbook -vv -i ocplabs-inventory.cfg ocplabs-host-deinstall.yaml >> ocplabs.log 2>&1 
  log info "Finished OpenShift Container Platform v3.6 deinstallation."
;;
*)
  show_usage
  exit
;;
esac
