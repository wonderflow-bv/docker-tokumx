all: start-cluster

mongodb-container:
	sudo docker pull "ankurcha/tokumx"

start-cluster:
	bash ./bin/start-cluster.sh

stop-cluster:
	bash ./bin/stop-cluster.sh

