svc_name := emojivoto-web

all: clean protoc webpack package-web test package

include ../common.mk

webpack:
	$(MAKE) -C webapp

package-web: webpack
	mkdir -p $(target_dir)/web
	cp web/favicon.ico $(target_dir)/web
	cp -a webapp/dist $(target_dir)

compile-server:
	GOOS=linux go build -v -o $(target_dir)/$(svc_name) cmd/server.go

compile-vote-bot:
	GOOS=linux go build -v -o $(target_dir)/emojivoto-vote-bot cmd/vote-bot/main.go

compile: compile-server compile-vote-bot

# Override common.mk: web needs frontend bundle before the container image is built.
package: protoc package-web compile build-container
