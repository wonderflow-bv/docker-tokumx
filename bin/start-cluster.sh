#!/bin/bash

### TODO 1  - create function `create_replica_set n` that creates n replica sets
### TODO 2  - create function `create_mongos` that instantiates mongos 
### TODO 3  - create a function that create n replica sets and n shards

NAME_INDEX=0
NAME_CFG_INDEX=0
NAME_MONGOS_INDEX=0
PORT_INDEX=10000
MONGOS_PORT=9999
IMAGE="mongo"
NET="my-mongo-cluster"
BIND_ADDRESS=0.0.0.0

start_mongod_docker() {
    echo `sudo docker run --detach --name mongo${NAME_INDEX} --net ${NET} ${IMAGE} mongod --replSet rs0 --shardsvr --bind_ip ${BIND_ADDRESS} --port ${PORT_INDEX}`
}

start_mongocfg_docker() {
    echo `sudo docker run --detach --name mongocfg${NAME_CFG_INDEX} --net ${NET} ${IMAGE} mongod --configsvr --bind_ip ${BIND_ADDRESS} --port ${PORT_INDEX}`
}

start_mongos_docker() {
    echo `sudo docker run --detach -p ${MONGOS_PORT}:${MONGOS_PORT} --name mongos${NAME_MONGOS_INDEX} --net ${NET} ${IMAGE} mongos --configdb ${1}:${2} --bind_ip ${BIND_ADDRESS} --port ${MONGOS_PORT}`
}

get_ip_from_id() {
    echo `sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${1}`
}

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
SHARD00_ID=`start_mongod_docker`
SHARD00_IP=`get_ip_from_id $SHARD00_ID`
echo "Your shard container ${SHARD00_ID} listen on ip: ${SHARD00_IP} (waiting that becomes ready)"
until sudo docker logs ${SHARD00_ID} | grep "waiting for connections on port" > /dev/null;
do
    sleep 2
done
echo NAME_INDEX $((NAME_INDEX++))
echo PORT_INDEX $((PORT_INDEX++))

SHARD01_ID=`start_mongod_docker`
SHARD01_IP=`get_ip_from_id $SHARD01_ID`
echo "Your shard container ${SHARD01_ID} listen on ip: ${SHARD01_IP} (waiting that becomes ready)"
until sudo docker logs ${SHARD01_ID} | grep "waiting for connections on port" > /dev/null;
do
    sleep 2
done
echo NAME_INDEX $((NAME_INDEX++))
echo PORT_INDEX $((PORT_INDEX++))

SHARD02_ID=`start_mongod_docker`
SHARD02_IP=`get_ip_from_id $SHARD02_ID`
echo "Your shard container ${SHARD02_ID} listen on ip: ${SHARD02_IP} (waiting that becomes ready)"
until sudo docker logs ${SHARD02_ID} | grep "waiting for connections on port" > /dev/null;
do
    sleep 2
done
echo NAME_INDEX $((NAME_INDEX++))
echo PORT_INDEX $((PORT_INDEX++))

echo "initialize replicaset"
sudo docker exec ${SHARD00_ID} mongo localhost:10000 --eval "rs.initiate();" > /dev/null
echo mongo ${SHARD00_IP}:10000 --eval "rs.initiate();"
sudo docker exec ${SHARD00_ID} mongo localhost:10000 --eval "rs.add(\"${SHARD01_IP}:10001\");" > /dev/null
echo mongo ${SHARD00_IP}:10000 --eval "rs.add(\"${SHARD01_IP}:10001\");"
sudo docker exec ${SHARD00_ID} mongo localhost:10000 --eval "rs.add(\"${SHARD02_IP}:10002\");" > /dev/null
echo mongo ${SHARD00_IP}:10000 --eval "rs.add(\"${SHARD02_IP}:10002\");"
until sudo docker logs ${SHARD00_ID} | grep "10002 is now in state SECONDARY" > /dev/null;
do
    sleep 2
done
echo "The shard replset is available now..."

CONFIG0_ID=`start_mongocfg_docker`
CONFIG0_IP=`get_ip_from_id $CONFIG0_ID`
echo "Your config container ${CONFIG0_ID} listen on ip: ${CONFIG0_IP} (waiting that becomes ready)"

until sudo docker logs ${CONFIG0_ID} | grep "waiting for connections on port" > /dev/null;
do
    sleep 2
done
echo NAME_CFG_INDEX $((NAME_CFG_INDEX++))
echo PORT_INDEX $((PORT_INDEX++))

echo "The config is available now..."

MONGOS0_ID=`start_mongos_docker ${CONFIG0_IP} $((PORT_INDEX - 1))`
MONGOS0_IP=`get_ip_from_id $MONGOS0_ID`
echo "Contacting shard and mongod containers"

until sudo docker logs ${MONGOS0_ID} | grep "config servers and shards contacted successfully" > /dev/null;
do
    sleep 2
done

# Add the shard
mongo ${MONGOS0_IP}:${MONGOS_PORT} --eval "sh.addShard(\"rs0/${SHARD00_IP}:10000,${SHARD01_IP}:10001,${SHARD02_IP}:10002\");"

echo "OK, you can connect to mongos using: "
echo "mongo ${MONGOS0_IP}:${MONGOS_PORT}"

