all: start-cluster

tokumx-container:
	sudo docker pull "ankurcha/tokumx"

start-cluster:
	bash ./bin/start-cluster.sh

stop-cluster:
	bash ./bin/stop-cluster.sh

rebuild-cluster:
	./stop-remove-restart-all.sh
