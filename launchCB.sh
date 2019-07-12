#!/bin/bash
# Automates configuration and installation of COSbench Helm chart
# on pre-existing OCP 4.1 cluster
# Uses cosbench helm chart from here
#   https://github.com/helm/charts/blob/master/stable/cosbench/values.yaml
#
# User must specify number of cosbench drivers
# USAGE: launchCB.sh <numdrivers>
# July 2019         John Harrigan 
###############################################################
PROGNAME=$(basename $0)
pause=60                 # time in sec to wait for pods to get READY

function error_exit
{
#        $1 is error string
#        $2 is LINENO where error ocurred
    echo "${PROGNAME} line#$2: ${1:-"Unknown Error"}" 1>&2
    exit 1
}

prompt_confirm() {
  while true; do
    read -r -n 1 -p "${1:-Continue?} [y/n]: " REPLY
    case $REPLY in
      [yY]) echo ; return 0 ;;
      [nN]) echo ; return 1 ;;
      *) printf " \033[31m %s \n\033[0m" "invalid input"
    esac 
  done  
}

if [[ "$#" -eq 1 ]]; then
    numdrvrs=$1
    if [ "$numdrvrs" -eq "$numdrvrs" ] 2>/dev/null; then
        echo "Creating one controller and $numdrvrs driver pods"
    else
        echo "Expects one argument - the number of drivers to run"
        echo "  - must be an integer"
        exit 1
    fi
else
    echo "Expects one argument - the number of drivers to run (integer)"
    exit 1
fi

#+++++++++++++++++++++++++++++
# Test for PREREQUISITES:
#   - OCP 4.1 Cluster
#   - export KUBECONFIG (as directed by openshift-installer results)
#   - openshift client command "oc"
#   - helm   <--  https://get.helm.sh/helm-v2.14.1-linux-amd64.tar.gz
DEPLIST="oc helm"
for dep in $DEPLIST; do
## DEBUG  echo $dep
  if [ "$(which $dep)" = "" ] ;then
    echo "This script requires $dep, please resolve and try again."
    exit 1
  fi
done

#+++++++++++++++++++++++++++++
# Check for clean environment: no ccb project and no tiller service
# Check for ccb project
oc get project ccb > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "Project ccb exists, please start with a clean environment"
    error_exit "FAIL project ccb found" $LINENO
fi
# Check if tiller service is already running (unclean cluster)
oc get pods -n kube-system | grep tiller > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "tiller service found running, please start with a clean environment"
    error_exit "FAIL tiller found running" $LINENO
fi

#+++++++++++++++++++++++++++++
# TILLER CONFIGURATION
# CONFIGURE Helm/Tiller (project kube-system)
echo "Configuring and starting tiller..."
oc create serviceaccount tiller -n kube-system 2>/dev/null || error_exit "FAIL serviceaccount" $LINENO
oc create clusterrolebinding tiller --clusterrole cluster-admin --serviceaccount=kube-system:tiller 2>/dev/null || error_exit "FAIL clusterrolebinding" $LINENO
helm init --service-account tiller || error_exit "FAIL helm init" $LINENO
echo "sleeping ${pause}s for previous cmd to complete..."
sleep $pause
# verify tiller-deploy is READY
oc get pods -n kube-system 2>/dev/null || echo "FAIL oc get pods" 
# WAIT for user to continue
echo "tiller-deploy should be READY, else exit"
prompt_confirm "Is tiller-deploy READY?" || error_exit "User aborted script"
echo "Continuing..."

#+++++++++++++++++++++++++++++
# INSTALL COSbench Helm Chart (project ccb):
oc adm policy add-scc-to-user anyuid system:serviceaccount:ccb:tiller 2>/dev/null || error_exit "FAIL adm policy tiller" $LINENO
oc adm policy add-scc-to-group anyuid system:authenticated 2>/dev/null || error_exit "FAIL system:authenticated" $LINENO
oc new-project ccb || error_exit "FAIL new-project" $LINENO
helm install stable/cosbench --name ccbhelm --set driver.replicaCount=$numdrvrs 2>/dev/null || error_exit "FAIL helm install" $LINENO 
echo "sleeping ${pause}s for previous cmd to complete..."
sleep $pause
oc get pods                   # see one cntrlr and $numdrvrs drivers
# WAIT for user to continue
echo "Pods cosbench-controller and driver(s) should be READY, else exit"
prompt_confirm "Are they READY?" || error_exit "User aborted script"
echo "Continuing..."

#+++++++++++++++++++++++++++++
# ACCESS COSbench Controller GUI
export POD_NAME=$(oc get pods --namespace ccb -l "app=cosbench,component=controller,release=ccbhelm" -o jsonpath="{.items[0].metadata.name}")
oc port-forward $POD_NAME 8080:19088 > /dev/null 2>&1 &  # run in backgrd

echo "Issued port-forward command, open WebBrowser  http://127.0.0.1:8080/controller/index.html"    
#  Driver 1: http://ccbhelm-cosbench-driver-0.ccbhelm-cosbench-driver:18088/driver
#  Driver 2: http://ccbhelm-cosbench-driver-1.ccbhelm-cosbench-driver:18088/driver
#  Driver 3: http://ccbhelm-cosbench-driver-2.ccbhelm-cosbench-driver:18088/driver

#+++++++++++++++++++++++++++++
# SUBMIT Workloads:
#  - Use Controller GUI           <-- submit new workloads
#  - login to controller pod
#     $ oc exec -it ccbX-cosbench-controller-58666997dc-6f85c -- /bin/bash
#     # ./cli.sh <workload.xml>
#     # cd conf
#     # cat controller.conf

#+++++++++++++++++++++++++++++
echo "To TEARDOWN:"
echo "   $ helm delete --purge ccbhelm"
echo "   $ oc delete project ccb"

