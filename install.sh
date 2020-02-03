#!/bin/bash

# Copyright The KubeDB Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# ref: https://github.com/kubernetes/charts/blob/master/stable/mongodb-replicaset/init/on-start.sh

set -eo pipefail

INIT_DIR="${INIT_DIR:-/scripts}"
DEST_DIR="${DEST_DIR:-/init-scripts}"

if [[ -d ${INIT_DIR} ]] && [[ -d ${DEST_DIR} ]]; then
    cp -a ${INIT_DIR}/* ${DEST_DIR}
fi

EXIT_CODE=0
if [[ "$SSL_MODE" != "disabled" ]];
then
    if [[ "$NODE_TYPE" != "standalone" ]];
    then
        kubectl get secrets -n $HOST_NAMESPACE $HOST_NAME || EXIT_CODE=$?
        if [[ $EXIT_CODE == 0 ]];
        then
            kubectl get secrets -n $HOST_NAMESPACE $HOST_NAME -o jsonpath='{.data.\ca\.crt}' | base64 -d >/var/run/mongodb/tls/ca.crt
            kubectl get secrets -n $HOST_NAMESPACE $HOST_NAME -o jsonpath='{.data.\tls\.crt}' | base64 -d >/var/run/mongodb/tls/mongo.pem
            kubectl get secrets -n $HOST_NAMESPACE $HOST_NAME -o jsonpath='{.data.\tls\.key}' | base64 -d >>/var/run/mongodb/tls/mongo.pem
            kubectl get secrets -n $HOST_NAMESPACE $CLIENT_CERT_NAME -o jsonpath='{.data.\tls\.crt}' | base64 -d >/var/run/mongodb/tls/client.pem
            kubectl get secrets -n $HOST_NAMESPACE $CLIENT_CERT_NAME -o jsonpath='{.data.\tls\.key}' | base64 -d >>/var/run/mongodb/tls/client.pem
            chmod 600 /var/run/mongodb/tls/ca.crt
            chmod 600 /var/run/mongodb/tls/mongo.pem
            chmod 600 /var/run/mongodb/tls/client.pem
        else
            echo "cert-secret $HOST_NAMESPACE/$HOST_NAME not ready"
        fi
    else
        kubectl get secrets -n $HOST_NAMESPACE $SERVER_CERT_NAME -o jsonpath='{.data.\ca\.crt}' | base64 -d >/var/run/mongodb/tls/ca.crt
        kubectl get secrets -n $HOST_NAMESPACE $SERVER_CERT_NAME -o jsonpath='{.data.\tls\.crt}' | base64 -d >/var/run/mongodb/tls/mongo.pem
        kubectl get secrets -n $HOST_NAMESPACE $SERVER_CERT_NAME -o jsonpath='{.data.\tls\.key}' | base64 -d >>/var/run/mongodb/tls/mongo.pem
        kubectl get secrets -n $HOST_NAMESPACE $CLIENT_CERT_NAME -o jsonpath='{.data.\tls\.crt}' | base64 -d >/var/run/mongodb/tls/client.pem
        kubectl get secrets -n $HOST_NAMESPACE $CLIENT_CERT_NAME -o jsonpath='{.data.\tls\.key}' | base64 -d >>/var/run/mongodb/tls/client.pem
    fi
else
    echo "TLS disabled"
fi

if [ -f "/configdb-readonly/mongod.conf" ]; then
    cp /configdb-readonly/mongod.conf /data/configdb/mongod.conf
else
    touch /data/configdb/mongod.conf
fi

if [ -f "/keydir-readonly/key.txt" ]; then
    cp /keydir-readonly/key.txt /data/configdb/key.txt
    chmod 600 /data/configdb/key.txt
fi
