# RGWOCP
Automates COSbench and Ceph RGW usage on Openshift

Scripts to automate running COSbench and Ceph RGW on OCP 4.1
  * launchCB.sh       - requires one argument (number of COSbench drivers)
  * launchRGW.sh

PRE-REQS:
  * local install of helm/tiller and openshift command line tool (oc)
  * access to Openshift cluster

## PROCEDURE

**Create OCP Cluster on AWS**
```
$ openshift-install --dir mycluster create cluster
...SNIP..
INFO Install complete!                            
INFO To access the cluster as the system:admin user when using 'oc', run 'export KUBECONFIG=/home/user/OCP/mycluster/auth/kubeconfig'
$ export KUBECONFIG=/home/user/OCP/mycluster/auth/kubeconfig
$ oc login -u "system:admin"
```
**Install and Run Scripts**
```
$ git clone https://github.com/jharriga/RGWOCP
$ cd RGWOCP
$ chmod 755 *.sh
$ ./launchCB.sh 2
Continuing...
Open WebBrowser  http://127.0.0.1:8080/controller/index.html

$ ./launchRGW.sh
AccessKey = W0D1KKQ0RAZKA11V73ZJ : SecretKey = qydp2aWjlLQBmkh7XXioe7ne3MA6NPlvRo9Ihw1F
rook-ceph-rgw service listening at = 172.30.92.76:8080
```
**TEARDOWN**
```
$ helm delete --purge ccbhelm
$ oc delete project ccb
$ oc delete project rook-ceph
$ openshift-install destroy cluster --dir mycluster/
```
  
