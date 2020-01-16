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


FROM alpine:3.11

# Install bash
RUN apk add --no-cache --upgrade bash

COPY replicaset.sh /usr/local/bin/
COPY replicaset-inmemory.sh /usr/local/bin/
COPY configdb.sh /usr/local/bin/
COPY sharding.sh /usr/local/bin/
COPY sharding-inmemory.sh /usr/local/bin/
COPY mongos.sh /usr/local/bin/
COPY disable-thp.sh /usr/local/bin/
COPY copy-config.sh /usr/local/bin/
COPY --from=builder peer-finder /usr/local/bin/

# Copy ssl-client-user to docker-entrypoint.d directory.
# xref: https://github.com/docker-library/mongo/issues/329#issuecomment-460858099
COPY 000-ssl-client-user.sh /docker-entrypoint-initdb.d/

RUN chmod -c 755 /usr/local/bin/peer-finder \
 /usr/local/bin/replicaset.sh \
 /usr/local/bin/replicaset-inmemory.sh \
 /usr/local/bin/configdb.sh \
 /usr/local/bin/sharding.sh \
 /usr/local/bin/sharding-inmemory.sh \
 /usr/local/bin/mongos.sh \
 /usr/local/bin/disable-thp.sh \
 /usr/local/bin/copy-config.sh

ENV SSL_MODE ""
ENV CLUSTER_AUTH_MODE ""

# For starting mongodb container
# default entrypoint of parent mongo:4.1.13
# ENTRYPOINT ["docker-entrypoint.sh"]

# For starting bootstraper init container (for mongodb replicaset)
# ENTRYPOINT ["peer-finder"]
