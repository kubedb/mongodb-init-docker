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

if [[ -d ${INIT_DIR} ]] && [[ -d ${DEST_DIR} ]]; then
    cp -a ${INIT_DIR}/* ${DEST_DIR}
fi


if [ -f "/configdb-readonly/mongod.conf" ]; then
    cp /configdb-readonly/mongod.conf /data/configdb/mongod.conf
else
    touch /data/configdb/mongod.conf
fi

if [ -f "/keydir-readonly/key.txt" ]; then
    cp /keydir-readonly/key.txt /data/configdb/key.txt
    chmod 600 /data/configdb/key.txt
    chown -R 1001:0 /data/configdb/key.txt
fi
