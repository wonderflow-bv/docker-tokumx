#!/bin/bash

### TODO 1  - create function `create_replica_set n` that creates n replica sets
### TODO 2  - create function `create_mongos` that instantiates mongos 
### TODO 3  - create a function that create n replica sets and n shards

#IMAGE="ankurcha/tokumx"
IMAGE="mongo"

set -e

if sudo docker ps | grep $IMAGE >/dev/null; then
    echo ""
    echo "It looks like you already have some containers running."
    echo "Please take them down before attempting to bring up another"
    echo "cluster with the following command:"
    echo ""
    echo "  make stop-cluster"
    echo ""

    exit 1
fi

# start docker containers for 3xreplicaset rs0
SHARD00_ID=$(sudo docker run -d $IMAGE mongod --replSet rs0 --shardsvr --logpath /dev/stdout --bind_ip 0.0.0.0 --port 10000)
#SHARD00_IP=$(sudo docker inspect ${SHARD00_ID} | grep "IPAddress" | cut -d':' -f2 | cut -d'"' -f2)
SHARD00_IP=`sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $SHARD00_ID`
#echo `sudo docker inspect --format '{{ .NetworkSettings.IPAddress }}' "$@" $SHARD00_ID`
echo "Your shard container ${SHARD00_ID} listen on ip: ${SHARD00_IP} (waiting that becomes ready)"
until sudo docker logs ${SHARD00_ID} | grep "replSet info you may need to run replSetInitiate" >/dev/null;
do
    sleep 2
done

SHARD01_ID=$(sudo docker run -d $IMAGE mongod --replSet rs0 --shardsvr --logpath /dev/stdout --bind_ip 0.0.0.0 --port 10001)
#SHARD01_IP=$(sudo docker inspect ${SHARD01_ID} | grep "IPAddress" | cut -d':' -f2 | cut -d'"' -f2)
SHARD01_IP=`sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $SHARD01_ID`
echo "Your shard container ${SHARD01_ID} listen on ip: ${SHARD01_IP} (waiting that becomes ready)"
until sudo docker logs ${SHARD01_ID} | grep "replSet info you may need to run replSetInitiate" >/dev/null;
do
    sleep 2
done

SHARD02_ID=$(sudo docker run -d $IMAGE mongod --replSet rs0 --shardsvr --logpath /dev/stdout --bind_ip 0.0.0.0 --port 10002)
#SHARD02_IP=$(sudo docker inspect ${SHARD02_ID} | grep "IPAddress" | cut -d':' -f2 | cut -d'"' -f2)
SHARD02_IP=`sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $SHARD02_ID`
echo "Your shard container ${SHARD02_ID} listen on ip: ${SHARD02_IP} (waiting that becomes ready)"
until sudo docker logs ${SHARD02_ID} | grep "replSet info you may need to run replSetInitiate" >/dev/null;
do
    sleep 2
done

echo "initialize replicaset"
mongo ${SHARD00_IP}:10000 --eval "rs.initiate({_id: \"rs0\", members: [{_id:0, host:\"${SHARD00_IP}:10000\"}, {_id:1, host:\"${SHARD01_IP}:10001\"}, {_id:2, host:\"${SHARD02_IP}:10002\"}]});"
until sudo docker logs ${SHARD00_ID} | grep "replSet PRIMARY" >/dev/null;
do
    sleep 2
done
echo "The shard replset is available now..."

CONFIG0_ID=$(sudo docker run -d $IMAGE mongod --configsvr  --dbpath /data/ --logpath /dev/stdout --bind_ip 0.0.0.0 --port 10000)
#CONFIG0_IP=$(sudo docker inspect ${CONFIG0_ID} | grep "IPAddress" | cut -d':' -f2 | cut -d'"' -f2)
CONFIG0_IP=`sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $CONFIG0_ID`
echo "Your config container ${CONFIG0_ID} listen on ip: ${CONFIG0_IP} (waiting that becomes ready)"

until sudo docker logs ${CONFIG0_ID} | grep "waiting for connections on port" >/dev/null;
do
    sleep 2
done

echo "The config is available now..."

MONGOS0_ID=$(sudo docker run -p 9999:9999 -d $IMAGE mongos --configdb ${CONFIG0_IP}:10000 --logpath /dev/stdout --bind_ip 0.0.0.0 --port 9999)
#MONGOS0_IP=$(sudo docker inspect ${MONGOS0_ID} | grep "IPAddress" | cut -d':' -f2 | cut -d'"' -f2)
MONGOS0_IP=`sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' $MONGOS0_ID`
echo "Contacting shard and mongod containers"

until sudo docker logs ${MONGOS0_ID} | grep "config servers and shards contacted successfully" >/dev/null;
do
    sleep 2
done

# Add the shard
mongo ${MONGOS0_IP}:9999 --eval "sh.addShard(\"rs0/${SHARD00_IP}:10000\");"

echo "OK, you can connect to mongos using: "
echo "mongo ${MONGOS0_IP}:9999"

