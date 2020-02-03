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

FROM debian:stretch as builder

ENV DEBIAN_FRONTEND noninteractive
ENV DEBCONF_NONINTERACTIVE_SEEN true

RUN set -x \
  && apt-get update \
  && apt-get install -y --no-install-recommends apt-transport-https ca-certificates curl unzip

RUN set -x                                                                                             \
  && curl -fsSL -o peer-finder https://github.com/kmodules/peer-finder/releases/download/v1.0.1-ac/peer-finder \
  && chmod 755 peer-finder
RUN set -x \
  && curl -L https://dl.k8s.io/v1.16.3/kubernetes-client-linux-amd64.tar.gz -o kubectl.tar.gz \
  && tar -xzvf kubectl.tar.gz \
  && chmod 755 kubernetes/client/bin/kubectl

FROM busybox

COPY replicaset.sh /scripts/replicaset.sh
COPY configdb.sh /scripts/configdb.sh
COPY sharding.sh /scripts/sharding.sh
COPY mongos.sh /scripts/mongos.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --from=builder peer-finder /scripts/peer-finder
COPY --from=builder kubernetes/client/bin/kubectl /usr/bin/kubectl

RUN chmod -c 755 /scripts/peer-finder \
 /scripts/replicaset.sh \
 /scripts/configdb.sh \
 /scripts/sharding.sh \
 /scripts/mongos.sh \
 /usr/local/bin/entrypoint.sh

ENV SSL_MODE ""
ENV CLUSTER_AUTH_MODE ""

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
