SHELL=/bin/bash -o pipefail

REGISTRY   ?= kubedb
BIN        ?= mongodb-init
IMAGE      := $(REGISTRY)/$(BIN)
TAG        ?= $(shell git describe --exact-match --abbrev=0 2>/dev/null || echo "")

DOCKER_PLATFORMS := linux/amd64 linux/arm64
PLATFORM         ?= linux/$(subst x86_64,amd64,$(subst aarch64,arm64,$(shell uname -m)))
VERSION          = $(TAG)_$(subst /,_,$(PLATFORM))

container-%:
	@$(MAKE) container \
	    --no-print-directory \
	    PLATFORM=$(subst _,/,$*)

push-%:
	@$(MAKE) push \
	    --no-print-directory \
	    PLATFORM=$(subst _,/,$*)

all-container: $(addprefix container-, $(subst /,_,$(DOCKER_PLATFORMS)))

all-push: $(addprefix push-, $(subst /,_,$(DOCKER_PLATFORMS)))

.PHONY: container
container:
	@echo "container: $(IMAGE):$(VERSION)"
	@docker buildx build --platform $(PLATFORM) --load --pull -t $(IMAGE):$(VERSION) -f Dockerfile .
	@echo

push: container
	@docker push $(IMAGE):$(VERSION)
	@echo "pushed: $(IMAGE):$(VERSION)"
	@echo

.PHONY: docker-manifest
docker-manifest:
	docker manifest create -a $(IMAGE):$(TAG) $(foreach PLATFORM,$(DOCKER_PLATFORMS),$(IMAGE):$(TAG)_$(subst /,_,$(PLATFORM)))
	docker manifest push $(IMAGE):$(TAG)

.PHONY: release
release:
	@$(MAKE) all-push docker-manifest --no-print-directory

.PHONY: version
version:
	@echo ::set-output name=version::$(VERSION)

.PHONY: fmt
fmt:
	@find . -path ./vendor -prune -o -name '*.sh' -exec shfmt -l -w -ci -i 4 {} \;

.PHONY: verify
verify: fmt
	@if !(git diff --exit-code HEAD); then \
		echo "files are out of date, run make fmt"; exit 1; \
	fi

.PHONY: ci
ci: verify

# make and load docker image to kind cluster
.PHONY: push-to-kind
push-to-kind: container
	@echo "Loading docker image into kind cluster...."
	@kind load docker-image $(IMAGE):$(VERSION)
	@echo "Image has been pushed successfully into kind cluster."
