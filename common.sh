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

# mongosh creates its config/history under $HOME on every run. The community
# image (mongodb-community-server ubi9-slim) sets HOME=/data/db owned by uid
# mongod, and mongos pods have no /data/db volume, so the pod's uid cannot write
# it. mongosh then prints "Warning: Could not access file: EACCES ..." on
# *stdout*, which corrupts every $(mongosh --quiet --eval ...) capture below.
if [[ ! -w "${HOME:-/}" ]]; then
    export HOME=/work-dir
fi

DEFAULT_WAIT_SECS=5
script_name=${0##*/}
count=0
log() {
    local msg="$1"
    local timestamp
    timestamp=$(date --iso-8601=ns)
    echo "[$timestamp] [$script_name] $msg" | tee -a /work-dir/log.txt
}

init() {
    count=0
}

exitScript() {
    total=10
    count=$((count + 1))
    if [ "$count" -ge "$total" ]; then
        exit 1
    fi
}

# mongosh renders the command status as `ok: 1`, `"ok":1` or, under --json,
# `"ok": {"$numberInt": "1"}`. Print just the digit, empty when absent. Done in
# bash because the community image (mongodb-community-server ubi9-slim) ships no
# jq/grep/awk/sed, and a missing binary inside an `if` silently reads as false.
okStatus() {
    local text="${1//[[:space:]]/}"
    text="${text//\"/}"
    local re='(^|[,{])ok:\{\$number[A-Za-z]+:([0-9]+)\}'
    if [[ "$text" =~ $re ]]; then
        echo "${BASH_REMATCH[2]}"
        return
    fi
    re='(^|[,{])ok:([0-9]+)'
    if [[ "$text" =~ $re ]]; then
        echo "${BASH_REMATCH[2]}"
    fi
}

retry() {
    local delay=1
    local numberOfTry=300
    local tryNo=1
    while [[ $tryNo -le $numberOfTry ]]; do
        str_command="$*"
        log "Running command $str_command . . ."
        # Capture stderr too: mongosh renders thrown errors (connection failures,
        # command errors) to stderr, and some builds do not feed them through a
        # pipe. Reading both streams keeps the classification below reliable.
        out=$("$@" 2>&1)
        log "$out"
        tryNo=$((tryNo + 1))

        if [[ "$(okStatus "$out")" == "1" ]]; then
            return 0
        elif [[ "$out" == *"HostUnreachable"* ]]; then
            sleep $delay
        elif [[ "$out" == *"Host not found"* ]]; then
            sleep $delay
        elif [[ "$out" == *"connection attempt failed: SocketException: stream truncated"* ]]; then
            # To handle ReconfigureTLS-situation like, current-pod has tls configured, but other peers dont
            return 0
        elif [[ "$out" == *"SocketException"* ]]; then
            # SocketException occurs in 3 commands[rs.add(), rs.addArb(), isMaster()] & 2 variation['connection attempt failed', 'host not found'] mainly.
            sleep $delay
        elif [[ "$(okStatus "$out")" == "0" ]]; then
            exit 1 # kill the container
        else
            return 0
        fi
    done
    exit 1
}

# bug: https://jira.mongodb.org/browse/SERVER-42065
# ref: https://www.golinuxcloud.com/linux-check-ipv6-enabled/#Method_1_Check_IPv6_module_status
ipv6=
if [ $(cat /sys/module/ipv6/parameters/disable) -eq "0" ]; then
    ipv6="--ipv6"
fi
