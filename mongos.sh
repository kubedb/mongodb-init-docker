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

set -eo pipefail

# ref: https://github.com/kubernetes/charts/blob/master/stable/mongodb-replicaset/init/on-start.sh
source /init-scripts/common.sh

export CONFIGDB_REPSET=${CONFIGDB_REPSET:-}
export SHARD_REPSETS=${SHARD_REPSETS:-}
export SERVICE_NAME=${SERVICE_NAME:-}
domain=$(awk -v s=search '{if($1 == s)print $3}' /etc/resolv.conf)
FULL_SVC="$SERVICE_NAME.$(awk -v s=search '{if($1 == s)print $2}' /etc/resolv.conf)"
SHARD_REPSETS=${SHARD_REPSETS//svc/$domain} # replace svc with $domain. xref: https://stackoverflow.com/a/13210909/4628962
SHARD_REPSETS_LIST=(${SHARD_REPSETS// / })  # make array that splits by space. https://stackoverflow.com/a/15400047/4628962

# awk -v s=search '{if($1 == s)print $3}' /etc/resolv.conf

if [[ "$AUTH" == "true" ]]; then
    admin_user="$MONGO_INITDB_ROOT_USERNAME"
    admin_password="$MONGO_INITDB_ROOT_PASSWORD"
    admin_creds=(-u "$admin_user" -p "$admin_password" --authenticationDatabase admin)
    auth_args=(--clusterAuthMode ${CLUSTER_AUTH_MODE} --sslMode ${SSL_MODE} --keyFile=/data/configdb/key.txt)
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

init
log "Ping Config Server replicaset : $CONFIGDB_REPSET"
until mongosh --quiet "$ipv6" --host "$CONFIGDB_REPSET" "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.adminCommand('ping')"; do
    sleep 1
    log "Ping to Config Server replicaset fails."
    exitScript
done

init
log "Check if Config Server primary node is UP!!"
until [[ $(mongosh --quiet "$ipv6" --host "$CONFIGDB_REPSET" "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "rs.status().hasOwnProperty('myState') && rs.status().myState==1;" | tail -1) == true ]]; do
    log "Primary Node of Config Server replicaset is not up"
    sleep 1
    exitScript
done

init
log "Waiting for mongos to be ready..."
until mongosh "$ipv6" --host localhost "${ssl_args[@]}" --json --eval "db.adminCommand('ping')"; do
    log "Retrying..."
    sleep 2
    exitScript
done

log "Add shard instances"
total=${#SHARD_REPSETS_LIST[*]}

if [ -n "$ipv6" ]; then
    retry retry mongosh admin "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --quiet --json --eval "db.adminCommand({'setDefaultRWConcern' : 1,'defaultWriteConcern' : {'w' : 'majority'}})"
else
    retry retry mongosh admin --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --quiet --json --eval "db.adminCommand({'setDefaultRWConcern' : 1,'defaultWriteConcern' : {'w' : 'majority'}})"
fi

log 'Shard list $total: ${SHARD_REPSETS_LIST[*]}'

for ((i = 0; i < $total; i++)); do
    repSet=${SHARD_REPSETS_LIST[$i]}
    log "Add shard: $repSet"
    mongosh "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "sh.addShard('$repSet');"
done

log "Ensure admin user credentials"
if [ -n "$ipv6" ]; then
    if [[ $(mongosh admin --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.system.users.find({user:'$admin_user'}).count()" --ipv6 | tail -1) == 0 ]]; then
        log "Creating admin user..."
        mongosh admin --host localhost "${ssl_args[@]}" --json --eval "db.createUser({user: '$admin_user', pwd: '$admin_password', roles: [{role: 'root', db: 'admin'}]})" --ipv6
    fi
else
    if [[ $(mongosh admin --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.system.users.find({user:'$admin_user'}).count()" | tail -1) == 0 ]]; then
        log "Creating admin user..."
        mongosh admin --host localhost "${ssl_args[@]}" --json --eval "db.createUser({user: '$admin_user', pwd: '$admin_password', roles: [{role: 'root', db: 'admin'}]})"
    fi
fi

mongosh "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "sh.enableSharding('kubedb-system');"
if [ -n "$ipv6" ]; then
    mongosh kubedb-system "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db['health-check'].createIndex({'id': 1});"
else
    mongosh kubedb-system --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db['health-check'].createIndex({'id': 1});"
fi
mongosh "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "sh.shardCollection('kubedb-system.health-check', {'id': 1});"

# Initialize Part for KubeDB. ref: https://github.com/docker-library/mongo/blob/a499e81e743b05a5237e2fd700c0284b17d3d416/3.4/docker-entrypoint.sh#L302
# Start
process_init_files() {
    export MONGO_INITDB_DATABASE="${MONGO_INITDB_DATABASE:-test}"
    log "Initialize init scripts"
    echo
    ls -la /docker-entrypoint-initdb.d
    for f in /docker-entrypoint-initdb.d/*; do
        case "$f" in
            *.sh)
                log "$0: running $f"
                . "$f"
                ;;
            *.js)
                log "$0: running $f 1"
                log "$(mongosh "$ipv6" --host localhost --quiet "$MONGO_INITDB_DATABASE" "${admin_creds[@]}" "${ssl_args[@]}" "$f")"
                ;;
            *) log "$0: ignoring $f" ;;
        esac
        echo
    done
    log "Done."
}

log "Ensure Initializing init scripts"
if [ -n "$ipv6" ]; then
    if [[ $(mongosh admin --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.kubedb.find({'_id': 'kubedb', 'kubedb': 'initialized'}).count()" --ipv6 | tail -1) == 0 ]] &&
        [[ $(mongosh admin --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.kubedb.insertOne({'_id': 'kubedb', 'kubedb': 'initialized'})" --ipv6 2>&1 | grep -c "E11000 duplicate key error collection: admin.kubedb") -eq 0 ]]; then
        process_init_files
    fi
else
    if [[ $(mongosh admin --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.kubedb.find({'_id': 'kubedb', 'kubedb': 'initialized'}).count()" | tail -1) == 0 ]] &&
        [[ $(mongosh admin --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.kubedb.insertOne({'_id': 'kubedb', 'kubedb': 'initialized'})" 2>&1 | grep -c "E11000 duplicate key error collection: admin.kubedb") -eq 0 ]]; then
        process_init_files
    fi
fi

#if [[ ${SSL_MODE} != "disabled" ]] && [[ -f "$client_pem" ]]; then
#    #xref: https://docs.mongodb.com/manual/tutorial/configure-x509-client-authentication/#procedures
#    log "Creating root user ${INJECT_USER} for SSL..."
#    out=$(mongosh admin "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.getSiblingDB(\"\$external\").runCommand({usersInfo: \"${INJECT_USER}\"})")
#    if echo "$out" | grep '${INJECT_USER}'; then
#        log "root user ${INJECT_USER} Already exists..."
#    else
#        mongosh admin "$ipv6" --host localhost "${admin_creds[@]}" "${ssl_args[@]}" --json --eval "db.getSiblingDB(\"\$external\").runCommand({createUser: \"${INJECT_USER}\",roles:[{role: 'root', db: 'admin'}],})"
#    fi
#fi

log "Good bye."
