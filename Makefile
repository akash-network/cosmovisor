include .env

REGISTRY           ?= ghcr.io
TAG_VERSION        ?= $(shell git describe --tags --abbrev=0 --match="v*")

IMAGE_NAME      := akash-network/cosmovisor:$(TAG_VERSION)-$(COSMOVISOR_VERSION)
IMAGE_BASE_NAME := akash-network/cosmovisor-base:$(COSMOVISOR_VERSION)

ifneq ($(REGISTRY),)
	IMAGE_NAME      := $(REGISTRY)/$(IMAGE_NAME)
	IMAGE_BASE_NAME := $(REGISTRY)/$(IMAGE_BASE_NAME)
endif

DOCKER_BUILD=docker build

SUBIMAGES = arm64 \
 amd64

.PHONY: gen-changelog
gen-changelog:
	@echo "generating changelog to changelog"
	./scripts/genchangelog.sh $(shell git describe --tags --abbrev=0) changelog.md

.PHONY: cosmovisor-%
cosmovisor-%:
	@echo "building $(IMAGE_NAME)-$*"
	$(DOCKER_BUILD) --platform=linux/$* -t $(IMAGE_NAME)-$* \
		--build-arg GOVERSION=$(GOVERSION) \
		--build-arg COSMOVISOR_VERSION=$(COSMOVISOR_VERSION) \
		--build-arg GO_GETTER_VERSION=$(GO_GETTER_VERSION) \
		--build-arg GO_TEMPLATE_VERSION=$(GO_TEMPLATE_VERSION) \
		-f Dockerfile .

.PHONY: cosmovisor-base-%
cosmovisor-base-%:
	@echo "building $(IMAGE_BASE_NAME)-$*"
	$(DOCKER_BUILD) --platform=linux/$* -t $(IMAGE_BASE_NAME)-$* \
		--build-arg GOVERSION=$(GOVERSION) \
		--build-arg COSMOVISOR_VERSION=$(COSMOVISOR_VERSION) \
		-f Dockerfile.cosmovisor .

.PHONY: cosmovisor
cosmovisor: $(patsubst %, cosmovisor-%,$(SUBIMAGES))

.PHONY: cosmovisor-base
cosmovisor-base: $(patsubst %, cosmovisor-base-%,$(SUBIMAGES))

.PHONY: docker-push-%
docker-push-%:
	docker push $(IMAGE_NAME)-$*

.PHONY: docker-push-base-%
docker-push-base-%:
	docker push $(IMAGE_BASE_NAME)-$*

.PHONY: docker-push
docker-push: $(patsubst %, docker-push-%,$(SUBIMAGES))

.PHONY: docker-push-base
docker-push-base: $(patsubst %, docker-push-base-%,$(SUBIMAGES))

.PHONY: manifest-create
manifest-create:
	@echo "creating manifest $(IMAGE_NAME)"
	docker manifest rm $(IMAGE_NAME) 2>/dev/null || true
	docker manifest create $(IMAGE_NAME) \
		$(foreach arch,$(SUBIMAGES), $(shell docker inspect $(IMAGE_NAME)-$(arch) | jq -r '.[].RepoDigests | .[0]'))

.PHONY: manifest-create-base
manifest-create-base:
	@echo "creating base manifest $(IMAGE_BASE_NAME)"
	docker manifest rm $(IMAGE_BASE_NAME) 2>/dev/null || true
	docker manifest create $(IMAGE_BASE_NAME) \
		$(foreach arch,$(SUBIMAGES), $(shell docker inspect $(IMAGE_BASE_NAME)-$(arch) | jq -r '.[].RepoDigests | .[0]'))

.PHONY: manifest-push
manifest-push:
	@echo "pushing manifest $(IMAGE_NAME)"
	docker manifest push $(IMAGE_NAME)

.PHONY: manifest-push-base
manifest-push-base:
	@echo "pushing base manifest $(IMAGE_BASE_NAME)"
	docker manifest push $(IMAGE_BASE_NAME)
