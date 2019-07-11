#!/bin/bash
#
# Uses rook to standup Ceph RGW
# PREREQS:
#    - OCP 4.1 cluster
#    - logged in as "system:admin"

VERSION="1.0.2"
TMPPATH="/tmp"
BASEPATH="${TMPPATH}/rook-${VERSION}/cluster/examples/kubernetes/ceph"

PROGNAME=$(basename $0)
pause=5         # time in sec to wait for pods to get READY

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

#-----------
# Confirm logged in as "system:admin"
oc config view --template='{{ range .contexts }}{{ if eq .name "'$(kubectl config current-context)'" }}Current user: {{ .context.user }}{{ end }}{{ end }}'
echo                            # add newline
prompt_confirm "Is Current user system:admin ?" || error_exit "User aborted" $LINENO

#-----------
# Get rook
wget "https://github.com/rook/rook/archive/v${VERSION}.tar.gz"
tar -xvf "v${VERSION}.tar.gz" -C $TMPPATH > /dev/null 2>&1 
prompt_confirm "Did rook wget succeed?" || error_exit "User aborted" $LINENO
rm -f "v${VERSION}.tar.gz"               # cleanup

#-----------
# Create the operators
echo "Creating the rook operators..."
oc create -f "${BASEPATH}/common.yaml" 
oc create -f "${BASEPATH}/operator-openshift.yaml" 
oc create -f "${BASEPATH}/cluster-test.yaml" 
oc create -f "${BASEPATH}/object-openshift.yaml" 
prompt_confirm "Did oc create cmds succeed?" || error_exit "User aborted" $LINENO

echo "Waiting for the rook-ceph pods to be READY."
echo "this usually takes 5 minutes..."
sleep $pause

#-----------
# Wait for the operators to be READY
#   1) rook-ceph-operator
#   2) rook-ceph-mon-a
#   3) rook-ceph-mgr-a
#   4) rook-ceph-osd-0; rook-ceph-osd-1; rook-ceph-osd-2
#   5) rook-ceph-rgw-my-store
#
#watch "oc get deployments -n rook-ceph"  
#
oc rollout status deployment rook-ceph-rgw-my-store -n rook-ceph
echo "oc rollout status deployment cmd completed"
oc get deployments -n rook-ceph
prompt_confirm "Are rook-ceph deployments READY?" || error_exit "User aborted" $LINENO

#-----------
echo "Creating S3 user"
oc create -f "${BASEPATH}/object-user.yaml"
oc -n rook-ceph get secrets >/dev/null 2>&1
AK=$(oc -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o yaml | grep AccessKey | awk '{print $2}' | base64 --decode)
SK=$(oc -n rook-ceph get secret rook-ceph-object-user-my-store-my-user -o yaml | grep SecretKey | awk '{print $2}' | base64 --decode)
echo "AccessKey = $AK : SecretKey = $SK"
IP=$(oc -n rook-ceph get svc | awk '/rook-ceph-rgw/{print $3}')
PT=$(oc -n rook-ceph get svc | awk '/rook-ceph-rgw/{print $5}' | cut -d/ -f1-1)
RGWE="${IP}:${PT}"
echo "rook-ceph-rgw service listening at = $RGWE"

prompt_confirm "Were AccessKey, SecretKey, rgw endpoint displayed?" || error_exit "User aborted" $LINENO
echo "Record the S3 credentials (AccessKey, SecretKey) and rgw (IP:PORT)"

#-----------
echo "Creating toolbox"
oc create -f "${BASEPATH}/toolbox.yaml" 
sleep $pause
oc get pods -n rook-ceph | grep "ceph-tools"
prompt_confirm "Is rook-ceph-tools pod RUNNING?" || error_exit "User aborted" $LINENO
echo "Created toolbox pod."

#----------
# Verification of Ceph and radosgw
echo "Checking cluster status (ceph -s on toolbox)"
echo "   $ oc get pods -n rook-ceph --no-headers=true | awk '/ceph-tools/{print $1}' | xargs -I {} oc exec {} -n rook-ceph -- ceph -s"
PODID=$(oc get pods -n rook-ceph --no-headers=true | awk '/ceph-tools/{print $1}')
oc exec $PODID -n rook-ceph -- ceph -s

echo "Verifying radosgw endpoint (curl $RGWE on toolbox)"
oc exec $PODID -n rook-ceph -- curl $RGWE
echo                                # add newline
echo "Login to toolbox with:"
echo "   $ oc exec -it -n rook-ceph $PODID bash"
echo
echo "$PROGNAME done."
echo

#-----------
# Cleanup - this is UGLY
# https://github.com/rook/rook/blob/master/Documentation/ceph-teardown.md
echo "When you are ready to TEARDOWN:"
echo "See this (messy)  https://github.com/rook/rook/blob/master/Documentation/ceph-teardown.md"
echo "OR destroy and restart your openshift environment" 
echo "Also, remove local copy of rook..."
echo "  rm -rf ${TMPPATH}/rook-${VERSION}"
