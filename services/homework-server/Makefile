GO ?= go
ROOT := ../..
DIST := $(ROOT)/dist

.PHONY: build test build-linux-arm64 build-linux-amd64 bundle bundle-amd64 clean
build:
	CGO_ENABLED=0 $(GO) build -trimpath -o $(DIST)/homework-server ./cmd/server
test:
	$(GO) test -race ./...
build-linux-arm64:
	CGO_ENABLED=0 GOOS=linux GOARCH=arm64 $(GO) build -trimpath -ldflags='-s -w' -o $(DIST)/homework-server-linux-arm64 ./cmd/server
build-linux-amd64:
	CGO_ENABLED=0 GOOS=linux GOARCH=amd64 $(GO) build -trimpath -ldflags='-s -w' -o $(DIST)/homework-server-linux-amd64 ./cmd/server
bundle: build-linux-arm64
	sh $(ROOT)/scripts/package-nas.sh arm64
bundle-amd64: build-linux-amd64
	sh $(ROOT)/scripts/package-nas.sh amd64
clean:
	rm -f $(DIST)/homework-server $(DIST)/homework-server-linux-arm64 $(DIST)/homework-server-linux-amd64
