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

# Re-points a KubeDB Courier branch member's cloned data directory at the branch's own
# hosts before mongod serves it. The operator runs it in the branch-recovery init
# container, on the database image (it needs that version's mongod), with:
#   BRANCH_COMPONENT  standalone | replicaset | configsvr | shard
#   BRANCH_RECOVERY   JSON {component, hosts: {srcPrefix: tgtPrefix}, fallbackConfig}
#
# The clone still carries the source's identity: its replica-set config lists the
# source's hosts, and config.shards / shardIdentity name the source's shards and config
# server. The clone's own oplog is replayed and checkpointed first, so nothing replayed
# later undoes the rewrite (branch-recovery.js). A marker keeps it to the first boot of
# a given clone; a refresh re-clones the data directory and the marker goes with it.
#
# Uses bash builtins only for text handling: the community image ships no grep/awk/sed.

set -e

DB="/data/db"
MARK="$DB/.kubedb-branch-recovered"

if [ -f "$MARK" ]; then
    echo "branch recovery already done for this clone"
    exit 0
fi
if [ ! -f "$DB/WiredTiger" ]; then
    echo "no cloned data directory to recover"
    touch "$MARK"
    exit 0
fi
if [ "$BRANCH_COMPONENT" = "standalone" ]; then
    echo "clone came from a standalone, nothing to re-point"
    touch "$MARK"
    exit 0
fi
SH=mongosh
command -v mongosh >/dev/null 2>&1 || SH=mongo

print_log() {
    local lines=()
    mapfile -t lines <"$1" 2>/dev/null || true
    local from=$((${#lines[@]} > 40 ? ${#lines[@]} - 40 : 0))
    echo "---- mongod log ($1) ----"
    printf '%s\n' "${lines[@]:from}"
}

# --fork hides the reason a start failed behind "child process failed", so surface the
# server log; a silent failure here is a branch that never serves its data.
start_mongod() {
    local log="$1"
    shift
    if ! mongod --dbpath "$DB" --port 27018 --bind_ip 127.0.0.1 --fork --logpath "$log" "$@"; then
        print_log "$log"
        exit 1
    fi
}

# Bring the data up to the top of its own oplog and checkpoint it. Without this, the
# later start with --replSet replays the oplog from the last stable checkpoint and
# could overwrite the sharding metadata re-pointed below.
echo "replaying the clone's own oplog"
if ! mongod --dbpath "$DB" --port 27018 --bind_ip 127.0.0.1 --fork --logpath /tmp/branch-replay.log \
    --setParameter recoverFromOplogAsStandalone=true \
    --setParameter takeUnstableCheckpointOnShutdown=true; then
    if [[ -f /tmp/branch-replay.log && "$(</tmp/branch-replay.log)" == *"no oplog found"* ]]; then
        # Nothing guarantees a given member holds the data: this volume has no oplog, so
        # it is no usable copy of the member. Empty it; the member initial-syncs from the
        # branch members that do hold the data.
        echo "the clone holds no oplog; emptying it so the member initial-syncs from the branch"
        shopt -s dotglob nullglob
        for f in "$DB"/*; do
            [ "${f##*/}" = "lost+found" ] || rm -rf "$f"
        done
        touch "$MARK"
        exit 0
    fi
    print_log /tmp/branch-replay.log
    exit 1
fi
mongod --dbpath "$DB" --shutdown

echo "re-pointing the clone at the branch's own hosts"
start_mongod /tmp/branch-rewrite.log
printf 'var BRANCH = %s;\n' "$BRANCH_RECOVERY" >/tmp/branch-rewrite.js
cat /init-scripts/branch-recovery.js >>/tmp/branch-rewrite.js
$SH --quiet --port 27018 /tmp/branch-rewrite.js
mongod --dbpath "$DB" --shutdown

touch "$MARK"
echo "branch recovery complete"
