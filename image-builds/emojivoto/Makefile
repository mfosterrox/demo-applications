include ./common.mk

.PHONY: web emoji-svc voting-svc integration-tests push

all: build integration-tests

build-base-docker-image:
	$(CONTAINER_CMD) build --platform linux/amd64 . -f Dockerfile-base \
		-t "$(REGISTRY_PREFIX)/emojivoto-svc-base:$(IMAGE_TAG)"

web:
	$(MAKE) -C emojivoto-web

emoji-svc:
	$(MAKE) -C emojivoto-emoji-svc

voting-svc:
	$(MAKE) -C emojivoto-voting-svc

build: web emoji-svc voting-svc

multi-arch:
	$(MAKE) -C emojivoto-web build-multi-arch
	$(MAKE) -C emojivoto-emoji-svc build-multi-arch
	$(MAKE) -C emojivoto-voting-svc build-multi-arch

deploy-to-minikube:
	$(MAKE) -C emojivoto-web build-container
	$(MAKE) -C emojivoto-emoji-svc build-container
	$(MAKE) -C emojivoto-voting-svc build-container
	kubectl delete -f emojivoto.yml || echo "ok"
	kubectl apply -f emojivoto.yml

deploy-to-docker-compose:
	docker-compose stop
	docker-compose rm -vf
	$(MAKE) -C emojivoto-web build-container
	$(MAKE) -C emojivoto-emoji-svc build-container
	$(MAKE) -C emojivoto-voting-svc build-container
	docker-compose -f ./docker-compose.yml up -d

push-%:
	$(CONTAINER_CMD) push "$(REGISTRY_PREFIX)/emojivoto-$*:$(IMAGE_TAG)"

push: push-svc-base push-emoji-svc push-voting-svc push-web
