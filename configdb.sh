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

sleep $DEFAULT_WAIT_SECS

if [[ "$AUTH" == "true" ]]; then
    admin_user="$MONGO_INITDB_ROOT_USERNAME"
    admin_password="$MONGO_INITDB_ROOT_PASSWORD"
    admin_creds=(-u "$admin_user" -p "$admin_password" --authenticationDatabase admin)
    auth_args=(--clusterAuthMode ${CLUSTER_AUTH_MODE} --sslMode ${SSL_MODE} --auth --keyFile=/data/configdb/key.txt)
fi

my_hostname=$(uname -n)
log "Bootstrapping MongoDB replica set member: $my_hostname"

log "Reading standard input..."
while read -ra line; do
    if [[ "${line}" == *"${my_hostname}"* ]]; then
        service_name="$line"
        continue
    fi
    peers=("${peers[@]}" "$line")
done

# set the cert files as ssl_args
if [[ ${SSL_MODE} != "disabled" ]]; then
    ca_crt=/var/run/mongodb/tls/ca.crt
    pem=/var/run/mongodb/tls/mongo.pem
    client_pem=/var/run/mongodb/tls/client.pem
    if [[ ! -f "$ca_crt" ]] || [[ ! -f "$pem" ]] || [[ ! -f "$client_pem" ]]; then
        log "ENABLE_SSL is set to true, but $ca_crt, $pem or $client_pem file does not exist"
        exit 1
    fi
    ssl_args=(--ssl --sslCAFile "$ca_crt" --sslPEMKeyFile "$pem")
    auth_args=(--clusterAuthMode ${CLUSTER_AUTH_MODE} --sslMode ${SSL_MODE} --sslCAFile "$ca_crt" --sslPEMKeyFile "$pem" --keyFile=/data/configdb/key.txt)
fi

log "Peers: ${peers[*]}"

log "Waiting for MongoDB to be ready..."
retry mongo "$ipv6" --host localhost "${ssl_args[@]}" --eval "db.adminCommand('ping')"

# check rs.isMaster() (we can run this without authentication) on self to see it is ready
retry mongo admin "$ipv6" --host localhost "${ssl_args[@]}" --quiet --eval "JSON.stringify(rs.isMaster())"

# check rs.isMaster() on each peer to see each of them are ready
for peer in "${peers[@]}"; do
    retry mongo admin "$ipv6" --host "$peer" "${ssl_args[@]}" --quiet --eval "JSON.stringify(rs.isMaster())"
done

log "Initialized."
sleep $DEFAULT_WAIT_SECS

if [[ $(mongo admin "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --quiet --eval "rs.status().myState") == '1' ]]; then
    log "($service_name) is already master"
    log "Good bye."
    exit 0
fi

if [[ $(mongo admin "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --quiet --eval "rs.status().myState") == '2' ]]; then
    log "($service_name) is already added in replicaset"
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
        log "Adding myself ($service_name) to replica set..."
        retry mongo admin "$ipv6" --host "$peer" "${admin_creds[@]}" "${ssl_args[@]}" --quiet --eval "JSON.stringify(rs.add('$service_name'))"

        sleep $DEFAULT_WAIT_SECS

        log 'Waiting for replica to reach SECONDARY state...'
        until printf '.' && [[ $(mongo admin "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --quiet --eval "rs.status().myState") == '2' ]]; do
            sleep 1
        done

        log '✓ Replica reached SECONDARY state.'

        log "Good bye."
        exit 0
    fi
done

# else initiate a replica set with yourself.
if mongo "$ipv6" --host localhost "${ssl_args[@]}" --eval "rs.status()" | grep "no replset config has been received"; then
    # Retrying command until successful
    log "Initiating a new replica set with myself ($service_name)..."
    retry mongo "$ipv6" --host localhost "${ssl_args[@]}" --quiet --eval "JSON.stringify(rs.initiate({'_id': '$replica_set', 'members': [{'_id': 0, 'host': '$service_name'}]}))"

    sleep $DEFAULT_WAIT_SECS

    log 'Waiting for replica to reach PRIMARY state...'
    until printf '.' && [[ $(mongo "$ipv6" --host localhost "${ssl_args[@]}" --quiet --eval "rs.isMaster().ismaster") == 'true' ]]; do
        sleep 1
    done

    log '✓ Replica reached PRIMARY state.'

    if [[ "$AUTH" == "true" ]]; then
        log "Creating admin user..."
        mongo admin "$ipv6" --host localhost "${ssl_args[@]}" --eval "db.createUser({user: '$admin_user', pwd: '$admin_password', roles: [{role: 'root', db: 'admin'}]})"
    fi

    log "Done."
fi

log "Good bye."
