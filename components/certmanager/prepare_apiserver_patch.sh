#!/bin/bash -eu
#
# Copyright (c) 2018 SAP SE or an SAP affiliate company. All rights reserved. This file is licensed under the Apache Software License, v. 2 except as noted otherwise in the LICENSE file
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

pushd "$KUBIFY_STATE_PATH" 1> /dev/null
master_count=$(terraform output master_count)
ip=$(terraform output master_ips)
bastion=$(terraform output bastion)
pem=$KUBIFY_STATE_PATH/gen/nodes_privatekey.pem
popd 1> /dev/null

doSSH() {
    # do ssh, ignore unknown hosts, don't save hosts, suppress warnings about saving hosts
    ssh -i $pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -o "ProxyCommand=ssh -i $pem -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -W %h:%p ubuntu@$bastion" core@$ip "$@" 2> >(grep -v "Warning: Permanently added .* to the list of known hosts\.")
}

if [ $# -gt 0 ] && [ $1 == "undo" ] ; then
    debug "Checking if apiserver is ready ..."
    uptodate=$(kubectl -n kube-system get ds kube-apiserver -o jsonpath='{.status.updatedNumberScheduled}')
    ready=$(kubectl -n kube-system get ds kube-apiserver -o jsonpath='{.status.numberReady}')
    while [[ $uptodate -lt 1 ]] || [[ $ready -lt 1 ]] ; do
        # wait until new apiserver is ready
        debug "Waiting until apiserver is ready ..."
        sleep 10
        uptodate=$(kubectl -n kube-system get ds kube-apiserver -o jsonpath='{.status.updatedNumberScheduled}')
        ready=$(kubectl -n kube-system get ds kube-apiserver -o jsonpath='{.status.numberReady}')
    done
    # undo patch
    echo "Undoing apiserver patch preparations."
    doSSH "sudo rm -f /etc/kubernetes/manifests/bootstrap-apiserver.yaml"
    doSSH "sudo rm -rf /etc/kubernetes/bootstrap-secrets"
else 
    if [ $master_count -gt 1 ] ; then
        # more than one master node, nothing to do
        echo "More than one master node detected. No preparations necessary."
        exit 0
    elif [ $master_count -eq 1 ] ; then
        # one master node, do something
        echo "Only one master node detected."
        echo "Applying apiserver patch preparations."
        doSSH "sudo cp -r -f /opt/bootkube/assets/tls/ /etc/kubernetes/bootstrap-secrets"
        doSSH "sudo cp -f /opt/bootkube/assets/bootstrap-manifests/bootstrap-apiserver.yaml /etc/kubernetes/manifests/"
    else 
        # something's off
        fail "Less thant one master node detected - something is strange. Aborting."
    fi
fi