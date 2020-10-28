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

DEFAULT_WAIT_SECS=5
script_name=${0##*/}

log() {
    local msg="$1"
    local timestamp
    timestamp=$(date --iso-8601=ns)
    echo "[$timestamp] [$script_name] $msg" | tee -a /work-dir/log.txt
}

retry() {
    local delay=1
    while true; do
        str_command="$*"
        log "Running command $str_command . . ."
        out=$("$@")
        log "$out"

        if [ "$(echo $out | jq -r '.ok')" == "1" ]; then
            return 0
        elif echo $out | grep "failed: Name or service not known"; then
            sleep $delay
        elif echo $out | jq -r '.errmsg' | grep "HostUnreachable"; then
            sleep $delay
        elif echo $out | jq -r '.errmsg' | grep "Host not found"; then
            sleep $delay
        else
            return 0
        fi
    done
}
