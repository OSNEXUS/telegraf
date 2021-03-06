UNAME := $(shell sh -c 'uname')
VERSION := $(shell sh -c 'git describe --always --tags')
ifdef GOBIN
PATH := $(GOBIN):$(PATH)
else
PATH := $(subst :,/bin:,$(GOPATH))/bin:$(PATH)
endif

# Standard Telegraf build
default: prepare build

# Only run the build (no dependency grabbing)
build:
	go build -o telegraf -ldflags \
		"-X main.Version=$(VERSION)" \
		./cmd/telegraf/telegraf.go

# Build with race detector
dev: prepare
	go build -race -o telegraf -ldflags \
		"-X main.Version=$(VERSION)" \
		./cmd/telegraf/telegraf.go

# Build linux 64-bit, 32-bit and arm architectures
build-linux-bins: prepare
	GOARCH=amd64 GOOS=linux go build -o telegraf_linux_amd64 \
								-ldflags "-X main.Version=$(VERSION)" \
								./cmd/telegraf/telegraf.go
	GOARCH=386 GOOS=linux go build -o telegraf_linux_386 \
								-ldflags "-X main.Version=$(VERSION)" \
								./cmd/telegraf/telegraf.go
	GOARCH=arm GOOS=linux go build -o telegraf_linux_arm \
								-ldflags "-X main.Version=$(VERSION)" \
								./cmd/telegraf/telegraf.go

# Get dependencies and use godep to checkout changesets
prepare:
	go get ./...
	go get github.com/tools/godep
	godep restore

# Run all docker containers necessary for unit tests
docker-run:
ifeq ($(UNAME), Darwin)
	docker run --name kafka \
		-e ADVERTISED_HOST=$(shell sh -c 'boot2docker ip || docker-machine ip default') \
		-e ADVERTISED_PORT=9092 \
		-p "2181:2181" -p "9092:9092" \
		-d spotify/kafka
endif
ifeq ($(UNAME), Linux)
	docker run --name kafka \
		-e ADVERTISED_HOST=localhost \
		-e ADVERTISED_PORT=9092 \
		-p "2181:2181" -p "9092:9092" \
		-d spotify/kafka
endif
	docker run --name mysql -p "3306:3306" -e MYSQL_ALLOW_EMPTY_PASSWORD=yes -d mysql
	docker run --name memcached -p "11211:11211" -d memcached
	docker run --name postgres -p "5432:5432" -d postgres
	docker run --name rabbitmq -p "15672:15672" -p "5672:5672" -d rabbitmq:3-management
	docker run --name opentsdb -p "4242:4242" -d petergrace/opentsdb-docker
	docker run --name redis -p "6379:6379" -d redis
	docker run --name aerospike -p "3000:3000" -d aerospike
	docker run --name nsq -p "4150:4150" -d nsqio/nsq /nsqd
	docker run --name mqtt -p "1883:1883" -d ncarlier/mqtt
	docker run --name riemann -p "5555:5555" -d blalor/riemann

# Run docker containers necessary for CircleCI unit tests
docker-run-circle:
	docker run --name kafka \
		-e ADVERTISED_HOST=localhost \
		-e ADVERTISED_PORT=9092 \
		-p "2181:2181" -p "9092:9092" \
		-d spotify/kafka
	docker run --name opentsdb -p "4242:4242" -d petergrace/opentsdb-docker
	docker run --name aerospike -p "3000:3000" -d aerospike
	docker run --name nsq -p "4150:4150" -d nsqio/nsq /nsqd
	docker run --name mqtt -p "1883:1883" -d ncarlier/mqtt
	docker run --name riemann -p "5555:5555" -d blalor/riemann

# Kill all docker containers, ignore errors
docker-kill:
	-docker kill nsq aerospike redis opentsdb rabbitmq postgres memcached mysql kafka mqtt riemann
	-docker rm nsq aerospike redis opentsdb rabbitmq postgres memcached mysql kafka mqtt riemann

# Run full unit tests using docker containers (includes setup and teardown)
test: docker-kill docker-run
	# Sleeping for kafka leadership election, TSDB setup, etc.
	sleep 60
	# SUCCESS, running tests
	go test -race ./...

# Run "short" unit tests
test-short:
	go test -short ./...

.PHONY: test
