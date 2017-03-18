#!/bin/bash

### TODO 1  - create function `create_replica_set n` that creates n replica sets
### TODO 2  - create function `create_mongos` that instantiates mongos 
### TODO 3  - create a function that create n replica sets and n shards

MONGOS_PORT=27017
SHARDS_PORT=27018
CONFIG_PORT=27019
IMAGE="mongo:3.2"
NET="my-mongo-cluster"
BIND_ADDRESS=0.0.0.0
DATA_ROOT=/data

set -e
docker network rm my-mongo-cluster
docker network create --driver bridge my-mongo-cluster

get_ip_from_id() {
    echo `docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' ${1}`
}

start_mongod_docker() {
    # echo "Starting a docker instance - shard${1}${2}"
    DATA_PATH="$DATA_ROOT/db/shard${1}${2}"
    echo `docker run --detach -v ${DATA_PATH}:${DATA_PATH} --net ${NET} ${IMAGE} mongod --replSet rs$1 --dbpath ${DATA_PATH} --shardsvr --bind_ip ${BIND_ADDRESS}`
}

start_mongocfg_docker() {
    CFG_PATH="DATA_ROOT/configdb/cfg${1}"
    echo `docker run --detach -v ${CFG_PATH}:${CFG_PATH} --net ${NET} ${IMAGE} mongod --dbpath ${CFG_PATH} --replSet cfg --configsvr --bind_ip ${BIND_ADDRESS}`
}

start_mongos_docker() {
    echo `docker run --detach -p ${MONGOS_PORT}:${MONGOS_PORT} --net ${NET} ${IMAGE} mongos --configdb ${1} --bind_ip ${BIND_ADDRESS}`
}

start_mongocfg_replica_docker() {
    CFG0_ID=`start_mongocfg_docker 0`
    CFG0_IP=`get_ip_from_id $CFG0_ID`
    until docker logs ${CFG0_ID} | grep "waiting for connections on port" > /dev/null;
    do
        sleep 2
    done

    CFG1_ID=`start_mongocfg_docker 1`
    CFG1_IP=`get_ip_from_id $CFG1_ID`
    until docker logs ${CFG1_ID} | grep "waiting for connections on port" > /dev/null
    do
        sleep 2
    done

    CFG2_ID=`start_mongocfg_docker 2`
    CFG2_IP=`get_ip_from_id $CFG2_ID`
    until docker logs ${CFG2_ID} | grep "waiting for connections on port" > /dev/null;
    do
        sleep 2
    done

    docker exec ${CFG0_ID} mongo --port ${CONFIG_PORT} --eval "rs.initiate();" > /dev/null;
    until docker logs ${CFG0_ID} | grep "PRIMARY" > /dev/null;
    do
        sleep 2
    done

    docker exec ${CFG0_ID} mongo --port ${CONFIG_PORT} --eval "cfg = rs.conf(); cfg.members[0].host = \"${CFG0_IP}:${CONFIG_PORT}\"; rs.reconfig(cfg);" > /dev/null;
    until docker logs ${CFG0_ID} | grep "This node is ${CFG0_IP}:${CONFIG_PORT} in the config" > /dev/null;
    do
        sleep 2
    done
    
    docker exec ${CFG0_ID} mongo --port ${CONFIG_PORT} --eval "rs.add(\"${CFG1_IP}:${CONFIG_PORT}\");" > /dev/null
    docker exec ${CFG0_ID} mongo --port ${CONFIG_PORT} --eval "rs.add(\"${CFG2_IP}:${CONFIG_PORT}\");" > /dev/null
    until docker logs ${CFG0_ID} | grep "Member ${CFG1_IP}:${CONFIG_PORT} is now in state SECONDARY" > /dev/null;
    do
        sleep 2
    done
    until docker logs ${CFG0_ID} | grep "Member ${CFG2_IP}:${CONFIG_PORT} is now in state SECONDARY" > /dev/null;
    do
        sleep 2
    done

    echo "cfg/${CFG0_IP}:${CONFIG_PORT},${CFG1_IP}:${CONFIG_PORT},${CFG2_IP}:${CONFIG_PORT}"
}

start_shard() {
    SHARD00_ID=`start_mongod_docker $1 0`
    SHARD00_IP=`get_ip_from_id $SHARD00_ID`
    echo "Your shard container ${SHARD00_ID} listen on ip: ${SHARD00_IP} (waiting that becomes ready)"
    until docker logs ${SHARD00_ID} | grep "waiting for connections on port" > /dev/null;
    do
        sleep 2
    done

    SHARD01_ID=`start_mongod_docker $1 1`
    SHARD01_IP=`get_ip_from_id $SHARD01_ID`
    echo "Your shard container ${SHARD01_ID} listen on ip: ${SHARD01_IP} (waiting that becomes ready)"
    until docker logs ${SHARD01_ID} | grep "waiting for connections on port" > /dev/null;
    do
        sleep 2
    done

    SHARD02_ID=`start_mongod_docker $1 2`
    SHARD02_IP=`get_ip_from_id $SHARD02_ID`
    echo "Your shard container ${SHARD02_ID} listen on ip: ${SHARD02_IP} (waiting that becomes ready)"
    until docker logs ${SHARD02_ID} | grep "waiting for connections on port" > /dev/null;
    do
        sleep 2
    done

    echo "initialize replicaset"
    docker exec ${SHARD00_ID} mongo --port ${SHARDS_PORT} --eval "rs.initiate();"
    until docker logs ${SHARD00_ID} | grep "PRIMARY" > /dev/null;
    do
        sleep 2
    done

    echo "patching host for docker"
    docker exec ${SHARD00_ID} mongo --port ${SHARDS_PORT} --eval "cfg = rs.conf(); cfg.members[0].host = \"${SHARD00_IP}:${SHARDS_PORT}\"; rs.reconfig(cfg);"
    until docker logs ${SHARD00_ID} | grep "This node is ${SHARD00_IP}:${SHARDS_PORT} in the config" > /dev/null;
    do
        sleep 2
    done
    
    docker exec ${SHARD00_ID} mongo --port ${SHARDS_PORT} --eval "rs.add(\"${SHARD01_IP}:${SHARDS_PORT}\");" > /dev/null
    docker exec ${SHARD00_ID} mongo --port ${SHARDS_PORT} --eval "rs.add(\"${SHARD02_IP}:${SHARDS_PORT}\");" > /dev/null
    until docker logs ${SHARD00_ID} | grep "Member ${SHARD01_IP}:${SHARDS_PORT} is now in state SECONDARY" > /dev/null;
    do
        sleep 2
    done
    until docker logs ${SHARD00_ID} | grep "Member ${SHARD02_IP}:${SHARDS_PORT} is now in state SECONDARY" > /dev/null;
    do
        sleep 2
    done
    echo "The shard replset is available now..."

    echo `docker exec ${MONGOS0_ID} mongo --eval "sh.addShard(\"rs$1/${SHARD00_IP}:${SHARDS_PORT},${SHARD01_IP}:${SHARDS_PORT},${SHARD02_IP}:${SHARDS_PORT}\");"`
    echo "Contacting shard and mongod containers rs$1"
    until docker logs ${MONGOS0_ID} | grep "config servers and shards contacted successfully" > /dev/null;
    do
        sleep 2
    done
}

if docker ps | grep $IMAGE >/dev/null; then
    echo ""
    echo "It looks like you already have some containers running."
    echo "Please take them down before attempting to bring up another"
    echo "cluster with the following command:"
    echo ""
    echo "  make stop-cluster"
    echo ""

    exit 1
fi

echo "Preparing config db..."

CONFIG0=`start_mongocfg_replica_docker`

echo "The config is available now @ ${CONFIG0}..."

MONGOS0_ID=`start_mongos_docker ${CONFIG0}`
MONGOS0_IP=`get_ip_from_id $MONGOS0_ID`

for i in `seq 0 $((${1:-1} - 1))`; do
    echo "Starting shard #$i creation..."
    start_shard $i
done

echo "OK, you can connect to mongos using: "
echo "mongo ${MONGOS0_IP}"
