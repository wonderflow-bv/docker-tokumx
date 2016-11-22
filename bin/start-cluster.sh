#!/bin/bash

### TODO 1  - create function `create_replica_set n` that creates n replica sets
### TODO 2  - create function `create_mongos` that instantiates mongos 
### TODO 3  - create a function that create n replica sets and n shards

MONGOS_PORT=27017
IMAGE="mongo"
NET="my-mongo-cluster"
BIND_ADDRESS=0.0.0.0

set -e

start_mongod_docker() {
    DATA_PATH=/data/shard${1}${2}
    sudo mkdir -p $DATA_PATH > /dev/null
    echo `sudo docker run --detach -v /data --net ${NET} ${IMAGE} mongod --replSet rs$1 --shardsvr --bind_ip ${BIND_ADDRESS}`
}

start_mongocfg_docker() {
    echo `sudo docker run --detach --net ${NET} ${IMAGE} mongod --configsvr --bind_ip ${BIND_ADDRESS}`
}

start_mongos_docker() {
    echo `sudo docker run --detach -p ${MONGOS_PORT}:${MONGOS_PORT} --net ${NET} ${IMAGE} mongos --configdb ${1} --bind_ip ${BIND_ADDRESS}`
}

get_ip_from_id() {
    echo `sudo docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${1}`
}

start_shard() {
    # start docker containers for 3xreplicaset rs0
    SHARD00_ID=`start_mongod_docker $1 0`
    SHARD00_IP=`get_ip_from_id $SHARD00_ID`
    echo "Your shard container ${SHARD00_ID} listen on ip: ${SHARD00_IP} (waiting that becomes ready)"
    until sudo docker logs ${SHARD00_ID} | grep "waiting for connections on port" > /dev/null;
    do
        sleep 2
    done

    SHARD01_ID=`start_mongod_docker $1 1`
    SHARD01_IP=`get_ip_from_id $SHARD01_ID`
    echo "Your shard container ${SHARD01_ID} listen on ip: ${SHARD01_IP} (waiting that becomes ready)"
    until sudo docker logs ${SHARD01_ID} | grep "waiting for connections on port" > /dev/null;
    do
        sleep 2
    done

    SHARD02_ID=`start_mongod_docker $1 2`
    SHARD02_IP=`get_ip_from_id $SHARD02_ID`
    echo "Your shard container ${SHARD02_ID} listen on ip: ${SHARD02_IP} (waiting that becomes ready)"
    until sudo docker logs ${SHARD02_ID} | grep "waiting for connections on port" > /dev/null;
    do
        sleep 2
    done

    echo "initialize replicaset"
    sudo docker exec ${SHARD00_ID} mongo --port 27018 --eval "rs.initiate();"
    until sudo docker logs ${SHARD00_ID} | grep "PRIMARY" > /dev/null;
    do
        sleep 2
    done

    echo "patching host for docker"
    sudo docker exec ${SHARD00_ID} mongo --port 27018 --eval "cfg = rs.conf(); cfg.members[0].host = \"${SHARD00_IP}:27018\"; rs.reconfig(cfg);"
    until sudo docker logs ${SHARD00_ID} | grep "This node is ${SHARD00_IP}:27018 in the config" > /dev/null;
    do
        sleep 2
    done
    
    sudo docker exec ${SHARD00_ID} mongo --port 27018 --eval "rs.add(\"${SHARD01_IP}:27018\");" > /dev/null
    sudo docker exec ${SHARD00_ID} mongo --port 27018 --eval "rs.add(\"${SHARD02_IP}:27018\");" > /dev/null
    until sudo docker logs ${SHARD00_ID} | grep "Member ${SHARD01_IP}:27018 is now in state SECONDARY" > /dev/null;
    do
        sleep 2
    done
    until sudo docker logs ${SHARD00_ID} | grep "Member ${SHARD02_IP}:27018 is now in state SECONDARY" > /dev/null;
    do
        sleep 2
    done
    echo "The shard replset is available now..."

    # Add the shard
    echo `sudo docker exec ${MONGOS0_ID} mongo --eval "sh.addShard(\"rs$1/${SHARD00_IP}:27018,${SHARD01_IP}:27018,${SHARD02_IP}:27018\");"`
    echo "Contacting shard and mongod containers rs$1"
    until sudo docker logs ${MONGOS0_ID} | grep "config servers and shards contacted successfully" > /dev/null;
    do
        sleep 2
    done
}

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

CONFIG0_ID=`start_mongocfg_docker`
CONFIG0_IP=`get_ip_from_id $CONFIG0_ID`
echo "Your config container ${CONFIG0_ID} listen on ip: ${CONFIG0_IP} (waiting that becomes ready)"

until sudo docker logs ${CONFIG0_ID} | grep "waiting for connections on port" > /dev/null;
do
    sleep 2
done

echo "The config is available now..."

MONGOS0_ID=`start_mongos_docker ${CONFIG0_IP}:27019`
MONGOS0_IP=`get_ip_from_id $MONGOS0_ID`

for i in `seq 0 $((${1:-1} - 1))`; do
    start_shard $i
done

echo "OK, you can connect to mongos using: "
echo "mongo ${MONGOS0_IP}"
