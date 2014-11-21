# docker-mongo

This is a [Docker](http://docker.io) project to bring up a local [TokuMX](http://www.tokutek.com/tokumx-for-mongodb/) cluster.

## Running

### Clone Repository

```bash
$ git clone https://github.com/ankurcha/docker-tokumx.git
$ cd docker-tokumx
$ make mongodb-container
```

The statement `make tokumx-container` will download the image from docker index.

### Launch cluster

```bash
$ make start-cluster
```

### Stop Cluster

```bash
$ make stop-cluster
```

