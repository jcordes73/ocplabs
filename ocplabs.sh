#!/bin/bash

trap interrupt 1 2 3 6 9 15

function interrupt()
{
  log error "OpenShift Enterprise v3.11 installation aborted"
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
  echo "Usage: ocplabs.sh <install|deinstall|cns-install|cns-deinstall|app-install> <parameters>"
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
MODE=unknown

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
    app-install)
      MODE=app-install
    ;;
  esac
done

if [ ! -f "ocplabs-ocp-inventory.cfg" ] ; then
  log error "Mandatory configuration-file ocplabs-ocp-inventory.cfg missing."
  exit
fi

case "$MODE" in
  install)

  bastion_host_preparation
  ocp_nodes_preparation
  ocp_nodes_prerequisites_check

  log info "Starting OpenShift Container Platform v3.11 installation."

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
  
  log info "Finished OpenShift Container Platform v3.11 installation."
;;
cns-install)

  log info "Starting OpenShift Container Platform v3.11 CNS installation."

  log info "Deployment started."

  ansible-playbook -vvv -i ocplabs-cns-inventory.cfg ocplabs-cns-nodes-setup.yaml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "CNS Installation failed. Aborting."
    exit
  fi

  log info "Finished OpenShift Container Platform v3.11 CNS installation."
;;
app-install)

  check_variables

  log info "Starting OpenShift Container Platform v3.11 Additional Application installation."

  log info "Deployment started."

  ansible-playbook -vvv -i ocplabs-cns-inventory.cfg ocplabs-ocp-additional-application.yaml >> ocplabs.log 2>&1

  ERROR_CODE=$?

  if [ $ERROR_CODE -ne 0 ]; then
    log error "Application Installation failed. Aborting."
    exit
  fi

  log info "Finished OpenShift Container Platform v3.11 Additional Application installation."
;;
deinstall)
  log info "Starting OpenShift Container Platform v3.11 deinstallation."  
  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg /usr/share/ansible/openshift-ansible/playbooks/adhoc/uninstall.yml >> ocplabs.log 2>&1
  ansible-playbook -vvv -i ocplabs-ocp-inventory.cfg ocplabs-ocp-nodes-deinstall.yaml >> ocplabs.log 2>&1 
  log info "Finished OpenShift Container Platform v3.11 deinstallation."
;;
cns-deinstall)
  log info "Starting OpenShift Container Platform v3.11 CNS deinstallation."
  ansible-playbook -vvv -i ocplabs-cns-inventory.cfg ocplabs-cns-nodes-deinstall.yaml >> ocplabs.log 2>&1
  log info "Finished OpenShift Container Platform v3.11 CNS deinstallation."
;;
*)
  show_usage
  exit
;;
esac
