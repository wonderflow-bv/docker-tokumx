all: start-cluster

tokumx-container:
	docker pull "ankurcha/tokumx"

start-cluster:
	bash ./bin/start-cluster.sh $(instances)

stop-cluster:
	bash ./bin/stop-cluster.sh

rebuild-cluster:
	bash ./bin/stop-remove-restart-all.sh $(instances)
