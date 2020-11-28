#!/bin/bash

helm list
helm delete --purge ccbhelm
oc delete route.route.openshift.io/ccbhelm-cosbench-controller -n ccb
oc delete project ccb
oc delete sa tiller -n kube-system
oc delete clusterrolebinding tiller -n kube-system
oc delete deployment.apps/tiller-deploy -n kube-system
oc delete service/tiller-deploy -n kube-system
