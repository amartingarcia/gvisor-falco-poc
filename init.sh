#!/bin/bash
# Declare Vars
KUBERNETES_VERSION='v1.26.1'
FALCO_VERSION='3.0.0'
FALCOSIDEKIK_VERSION='0.5.16'
KUBEPROMETHEUSSTACK_VERSION='45.3.0'
CLUSTER_NAME='falco'
CONFIG_PATH='config'

_help() {
	echo ""
	echo "Use: $0 -o (minikube|gvisor|falco|delete)"
 	echo ""
}

_minikube_ip() {
  	export MINIKUBE_IP=$(minikube ip -p ${CLUSTER_NAME})
}
_pre_minikube(){
    echo "[FALCO] Configure Prerequisites"
    mkdir -p ~/.minikube/files/etc/ssl/certs
    cp ${CONFIG_PATH}/minikube-audit-policy.yaml ~/.minikube/files/etc/ssl/certs/minikube-audit-policy.yaml
    cp ${CONFIG_PATH}/minikube-webhook-config.yaml ~/.minikube/files/etc/ssl/certs/minikube-webhook-config.yaml
}

_minikube() {
  	echo "[GLOBAL] Install Virtualbox"
  	sudo apt-get install virtualbox -y
	
  	echo "[GLOBAL] Create Cluster on Minikube"
	minikube start -p ${CLUSTER_NAME}                                                             	\
        --extra-config=apiserver.audit-policy-file=/etc/ssl/certs/minikube-audit-policy.yaml      	\
        --extra-config=apiserver.audit-log-path=-                                                 	\
        --extra-config=apiserver.audit-webhook-config-file=/etc/ssl/certs/minikube-webhook-config 	\
        --extra-config=apiserver.audit-webhook-batch-max-size=10                                  	\
        --extra-config=apiserver.audit-webhook-batch-max-wait=5s                                  	\
        --cpus=4                                                                                  	\
        --kubernetes-version=${KUBERNETES_VERSION}                                                  \
        --container-runtime=containerd 															  	\
    	--docker-opt containerd=/var/run/containerd/containerd.sock 							  	\
		--driver=virtualbox
	
  	echo "[GLOBAL] Enable ingress and gvisor on Minikube"
  	minikube addons enable ingress -p ${CLUSTER_NAME}
	minikube addons enable gvisor -p ${CLUSTER_NAME}
}

_gvisor(){
  	echo "[GVISOR] Create Kubernetes resources"
	kubectl apply -f ${CONFIG_PATH}/gvisor.yaml -f ${CONFIG_PATH}/non-gvisor.yaml
}

_falco() {
  	echo "[FALCO] Install Falco"
	helm repo add falcosecurity https://falcosecurity.github.io/charts
	helm repo update
	helm upgrade --install falco                 \
    		falcosecurity/falco                  \
      		-f ${CONFIG_PATH}/helm-falco.yaml    \
    		-n falco                             \
    		--create-namespace                   \
      		--version ${FALCO_VERSION}
}

_kube_prometheus_stack() {
  	_minikube_ip
  
  	echo "[FALCO] Install kube-prometheus-stack"
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install                                                           \
    		kube-prometheus-stack prometheus-community/kube-prometheus-stack         \
			-n kube-prometheus-stack                                                 \
    		--set grafana.enabled="false"                                            \
			--set alertmanager.ingress.enabled="true"                                \
			--set alertmanager.ingress.hosts="{alertmanager.${MINIKUBE_IP}.nip.io}"  \
    		--create-namespace                                                       \
    		--version ${KUBEPROMETHEUSSTACK_VERSION}
}

_falco_sidekick() {
  	_minikube_ip

  	echo "[FALCO] Install falcosidekick"
  	helm upgrade --install falcosidekick                                                \
    		falcosecurity/falcosidekick                                                 \
			-n falco -f ${CONFIG_PATH}/helm-sidekick.yaml                               \
    		--set webui.enabled="true"                                                  \
			--set webui.ingress.enabled="true"                                          \
			--set webui.ingress.hosts[0].host="falcosidekick-ui.${MINIKUBE_IP}.nip.io"  \
			--version ${FALCOSIDEKIK_VERSION}
}

_delete_environment() {
  	echo "[FALCO] Delete environment"
	minikube delete -p ${CLUSTER_NAME}
}

# Args parsing
while getopts 'o:h' OPTION; do
  case "${OPTION}" in
    o)
      ACTION="${OPTARG}"
    ;;

    h|?|*)
      _help
      exit 1
    ;;

  esac
done

# MAIN
case ${ACTION} in
  'minikube')
    _pre_minikube
    _minikube
  ;;

  'gvisor')
    _gvisor
  ;;

  'falco')
	_falco
    _kube_prometheus_stack
    _falco_sidekick
  ;;

  'delete')
    _delete_environment
  ;;

  *)
    echo "ERROR: Argument not valid, need some 'action'"
    _help
  ;;
esac
