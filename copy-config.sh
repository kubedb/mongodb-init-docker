#!/bin/sh

set -xe

if [ -f "/configdb-readonly/mongod.conf" ]; then
        cp /configdb-readonly/mongod.conf /data/configdb/mongod.conf
else
        touch /data/configdb/mongod.conf
fi

if [ -f "/keydir-readonly/key.txt" ]; then
        cp /keydir-readonly/key.txt /data/configdb/key.txt
        chmod 600 /data/configdb/key.txt
fi

if [ -f "/keydir-readonly/ca.cert" ]; then
        cp /keydir-readonly/ca.cert /data/configdb/ca.cert
        chmod 600 /data/configdb/ca.cert
fi

if [ -f "/keydir-readonly/ca.key" ]; then
        cp /keydir-readonly/ca.key /data/configdb/ca.key
        chmod 600 /data/configdb/ca.key
fi

if [ -f "/keydir-readonly/mongo.pem" ]; then
        cp /keydir-readonly/mongo.pem /data/configdb/mongo.pem
        chmod 600 /data/configdb/mongo.pem
fi

if [ -f "/keydir-readonly/client.pem" ]; then
        cp /keydir-readonly/client.pem /data/configdb/client.pem
        chmod 600 /data/configdb/client.pem
fi

cp /usr/local/bin/replicaset.sh /data/configdb/replicaset.sh
chmod 777 /data/configdb/replicaset.sh

cp /usr/local/bin/replicaset-inmemory.sh /data/configdb/replicaset-inmemory.sh
chmod 777 /data/configdb/replicaset-inmemory.sh

cp /usr/local/bin/configdb.sh /data/configdb/configdb.sh
chmod 777 /data/configdb/configdb.sh

cp /usr/local/bin/sharding.sh /data/configdb/sharding.sh
chmod 777 /data/configdb/sharding.sh

cp /usr/local/bin/sharding-inmemory.sh /data/configdb/sharding-inmemory.sh
chmod 777 /data/configdb/sharding-inmemory.sh

cp /usr/local/bin/mongos.sh /data/configdb/mongos.sh
chmod 777 /data/configdb/mongos.sh

cp /usr/local/bin/peer-finder /data/configdb/peer-finder
chmod 777 /data/configdb/peer-finder

cp /usr/local/bin/disable-thp.sh /data/configdb/disable-thp.sh
chmod 777 /data/configdb/disable-thp.sh

ls -lrt /data/configdb
exit 0
