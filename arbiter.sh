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

source /init-scripts/common.sh
replica_set="$REPLICA_SET"
script_name=${0##*/}

sleep "$DEFAULT_WAIT_SECS"

if [[ "$AUTH" == "true" ]]; then
    admin_user="$MONGO_INITDB_ROOT_USERNAME"
    admin_password="$MONGO_INITDB_ROOT_PASSWORD"
    admin_creds=(-u "$admin_user" -p "$admin_password" --authenticationDatabase admin)
    auth_args=(--clusterAuthMode ${CLUSTER_AUTH_MODE} --sslMode ${SSL_MODE} --auth --keyFile=/data/configdb/key.txt)
fi

function get_governing_service_name {
    local my_hostname=$(uname -n)
    log "Bootstrapping MongoDB replica set arbiter member: $my_hostname"
    service_name="${my_hostname}.${GOVERNING_SERVICE_NAME}.${POD_NAMESPACE}.svc"
}
get_governing_service_name

function get_peers {
    local HOSTS=$(echo "$1" | tr "/" "\n")
    # convert to an array
    local pods=($HOSTS)
    # first index contains replicaset name. remove it
    unset pods[0]
    # pods are comma separated. make it an array.
    local HOSTS=$(echo "${pods[@]}" | tr "," "\n")
    peers=($HOSTS)
}

if [[ "$SHARD_TOPOLOGY_TYPE" == 'shard' ]]; then
    log "finding peers for shard"
    get_peers "$SHARD_DSN"
else
    log "finding peers for replicaset"
    get_peers "$REPLICASET_DSN"
fi

# set the cert files as ssl_args
if [[ ${SSL_MODE} != "disabled" ]]; then
    ca_crt=/var/run/mongodb/tls/ca.crt
    pem=/var/run/mongodb/tls/mongo.pem
    client_pem=/var/run/mongodb/tls/client.pem
    if [[ ! -f "$ca_crt" ]] || [[ ! -f "$pem" ]] || [[ ! -f "$client_pem" ]]; then
        log "ENABLE_SSL is set to true, but $ca_crt or $pem or $client_pem file does not exist"
        exit 1
    fi

    ssl_args=(--tls --tlsCAFile "$ca_crt" --tlsCertificateKeyFile "$pem")
    auth_args=(--clusterAuthMode ${CLUSTER_AUTH_MODE} --sslMode ${SSL_MODE} --tlsCAFile "$ca_crt" --tlsCertificateKeyFile "$pem" --keyFile=/data/configdb/key.txt)
fi

function removeSelf() {
    for peer in "${peers[@]}"; do
        if [[ $peer == *"$service_name"* ]]; then # finding myself
            remove=$peer
        fi
    done
    peers=(${peers[@]/$remove/})
}
removeSelf
log "Peers: ${peers[*]}"

domain=$(awk -v s=search '{if($1 == s)print $3}' /etc/resolv.conf)
service_name=${service_name//svc/$domain} # replace svc with $domain.
log "Arbiter service name: $service_name"

log "Waiting for this arbiter & all peers to be ready..."
retry mongo "$ipv6" --host localhost "${ssl_args[@]}" --eval "db.adminCommand('ping')"
for peer in "${peers[@]}"; do
    retry mongo admin "$ipv6" --host "$peer" "${ssl_args[@]}" --quiet --eval "JSON.stringify(rs.isMaster())"
done

log "Initialized."
sleep "$DEFAULT_WAIT_SECS"

rsStatus=$(mongo admin "$ipv6" --host localhost "${ssl_args[@]}" --quiet --eval "rs.status()")
# no need to retry for the first time
if [ "$(echo "$rsStatus" | jq -r '.ok')" == "0" ] && [ "$(echo "$rsStatus" | jq -r '.codeName')" == "NotYetInitialized" ]; then
    log "Not added to any replicaSet yet"
else
    retry mongo admin "$ipv6" --host localhost "${ssl_args[@]}" --quiet --eval "rs.status().myState"
fi

# myState : 1 - Primary, 2 - Secondary, 7 - Arbiter
if [[ $(mongo admin "$ipv6" --host localhost "${ssl_args[@]}" --quiet --eval "rs.status().myState") == '7' ]]; then
    log "($service_name) is already added as arbiter in replicaset"
    log "Good bye."
    exit 0
fi

# try to find a master and add yourself to its replica set.
for peer in "${peers[@]}"; do
    # re-check rs.isMaster() on the peer to see it is ready
    retry mongo admin "$ipv6" --host "$peer" "${admin_creds[@]}" "${ssl_args[@]}" --quiet --eval "JSON.stringify(rs.isMaster())"
    out=$(mongo admin "$ipv6" --host "$peer" "${admin_creds[@]}" "${ssl_args[@]}" --quiet --eval "JSON.stringify(rs.isMaster())")
    log "$out"
    if echo "$out" | jq -r '.ismaster' | grep 'true'; then
        log "Found master: $peer"

        # Retrying command until successful
        log "Adding myself ($service_name) as arbiter to replica set..."
        retry mongo admin "$ipv6" --host "$peer" "${admin_creds[@]}" "${ssl_args[@]}" --quiet --eval "JSON.stringify(rs.addArb('$service_name'))"

        sleep "$DEFAULT_WAIT_SECS"

        log 'Waiting for replica to reach ARBITER state...'
        until printf '.' && [[ $(mongo admin "$ipv6" --host localhost "${ssl_args[@]}" --quiet --eval "rs.status().myState") == '7' ]]; do
            sleep 1
        done

        log '✓ Replica reached ARBITER state.'
        log "Good bye."
        exit 0
    fi
done
