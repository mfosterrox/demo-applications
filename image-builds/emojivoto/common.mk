IMAGE_TAG ?= 0.1.0
REGISTRY_PREFIX ?= quay.io/mfoster
CONTAINER_CMD ?= podman
BASE_IMAGE ?= $(REGISTRY_PREFIX)/emojivoto-svc-base:$(IMAGE_TAG)

.PHONY: package protoc test

target_dir := target

clean:
	rm -rf gen
	rm -rf $(target_dir)
	mkdir -p $(target_dir)
	mkdir -p gen

# Prefer system protoc (e.g. brew install protobuf); fall back to bin/protoc downloader.
PROTOC ?= $(shell command -v protoc 2>/dev/null || echo ../bin/protoc)
EMOJIVOTO_ROOT := $(abspath ..)
EMOJIVOTO_GOMODCACHE := $(EMOJIVOTO_ROOT)/.go-modcache
EMOJIVOTO_GOBIN := $(EMOJIVOTO_ROOT)/.go-bin
# Isolate from broken shell GOPATH/GOMODCACHE (e.g. paths starting with ~)
export GOPATH := $(EMOJIVOTO_ROOT)/.go-path
export GOMODCACHE := $(EMOJIVOTO_GOMODCACHE)
export PATH := $(EMOJIVOTO_GOBIN):$(PATH)

protoc:
	@mkdir -p "$(EMOJIVOTO_GOMODCACHE)" "$(EMOJIVOTO_GOBIN)" "$(GOPATH)" gen
	@command -v protoc-gen-go >/dev/null 2>&1 || ( \
		echo "Installing protoc-gen-go into $(EMOJIVOTO_GOBIN)..." >&2; \
		GOBIN="$(EMOJIVOTO_GOBIN)" GOPATH="$(GOPATH)" GOMODCACHE="$(EMOJIVOTO_GOMODCACHE)" \
			go install google.golang.org/protobuf/cmd/protoc-gen-go@v1.36.8; \
	)
	@command -v protoc-gen-go-grpc >/dev/null 2>&1 || ( \
		echo "Installing protoc-gen-go-grpc into $(EMOJIVOTO_GOBIN)..." >&2; \
		GOBIN="$(EMOJIVOTO_GOBIN)" GOPATH="$(GOPATH)" GOMODCACHE="$(EMOJIVOTO_GOMODCACHE)" \
			go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@v1.5.1; \
	)
	$(PROTOC) -I .. ../proto/*.proto --go_out=paths=source_relative:./gen --go-grpc_out=paths=source_relative:./gen

package: protoc compile build-container

build-container:
	$(CONTAINER_CMD) build .. -t "$(REGISTRY_PREFIX)/$(svc_name):$(IMAGE_TAG)" \
		--build-arg svc_name=$(svc_name) \
		--build-arg BASE_IMAGE=$(BASE_IMAGE)

build-multi-arch:
	$(CONTAINER_CMD) buildx build .. -t "$(REGISTRY_PREFIX)/$(svc_name):$(IMAGE_TAG)" \
		--build-arg svc_name=$(svc_name) \
		--build-arg BASE_IMAGE=$(BASE_IMAGE) \
		-f ../Dockerfile-multi-arch --platform linux/amd64,linux/arm64,linux/arm/v7 --push

compile:
	@mkdir -p $(target_dir)
	GOOS=linux go build -v -o $(target_dir)/$(svc_name) cmd/server.go

test:
	go test ./...

run:
	go run cmd/server.go
