#!/bin/sh

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

if [[ "$SSL_MODE" != "disabled" ]]; then
    # Creating client.pem file combining client crt and key
    cat /client-cert/tls.crt >/var/run/mongodb/tls/client.pem
    if [[ $(tail -c1 /var/run/mongodb/tls/client.pem) != "\n" ]]; then # Checking if the crt file has a trailing newline, if not then added a newline
        echo >>/var/run/mongodb/tls/client.pem
    fi
    cat /client-cert/tls.key >>/var/run/mongodb/tls/client.pem

    # Creating mongo.pem file combining server crt and key
    cat /server-cert/tls.crt >/var/run/mongodb/tls/mongo.pem
    if [[ $(tail -c1 /var/run/mongodb/tls/mongo.pem) != "\n" ]]; then # Checking if the crt file has a trailing newline, if not then added a newline
        echo >>/var/run/mongodb/tls/mongo.pem
    fi
    cat /server-cert/tls.key >>/var/run/mongodb/tls/mongo.pem

    # used cat over cp so that ca.crt has 444 permission
    cat /server-cert/ca.crt >/var/run/mongodb/tls/ca.crt
fi

client_pem=/var/run/mongodb/tls/client.pem
if [[ "$SSL_MODE" != "disabled" ]] && [[ -f "$client_pem" ]]; then
    user=$(openssl x509 -in "$client_pem" -inform PEM -subject -nameopt RFC2253 -noout)
    user=$(echo ${user#"subject="})
    export INJECT_USER=$user

    envsubst '${INJECT_USER}' <${INIT_DIR}/replicaset.sh >${DEST_DIR}/replicaset.sh
    envsubst '${INJECT_USER}' <${INIT_DIR}/sharding.sh >${DEST_DIR}/sharding.sh
    envsubst '${INJECT_USER}' <${INIT_DIR}/mongos.sh >${DEST_DIR}/mongos.sh

    ls -l ${INIT_DIR}
    echo "----"
    ls -l ${DEST_DIR}
    rm ${INIT_DIR}/replicaset.sh ${INIT_DIR}/mongos.sh ${INIT_DIR}/sharding.sh
    chmod -c 755 ${DEST_DIR}/replicaset.sh ${DEST_DIR}/sharding.sh ${DEST_DIR}/mongos.sh
fi

if [[ -d ${INIT_DIR} ]]; then
  echo "init dir"
fi

if [[ -d ${DEST_DIR} ]]; then
  echo "dest dir"
fi

if [[ -d ${INIT_DIR} ]] && [[ -d ${DEST_DIR} ]]; then
    cp -a ${INIT_DIR}/* ${DEST_DIR}
fi

echo "after if"
ls -l ${DEST_DIR}


if [ -f "/configdb-readonly/mongod.conf" ]; then
    cp /configdb-readonly/mongod.conf /data/configdb/mongod.conf
else
    touch /data/configdb/mongod.conf
fi

if [ -f "/configdb-readonly/configuration.js" ]; then
    cp /configdb-readonly/configuration.js /data/configdb/configuration.js
fi

if [ -f "/keydir-readonly/key.txt" ]; then
    cp /keydir-readonly/key.txt /data/configdb/key.txt
     chmod 400 /data/configdb/key.txt
fi
