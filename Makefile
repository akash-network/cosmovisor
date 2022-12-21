include .env

REGISTRY           ?= ghcr.io
TAG_VERSION        ?= $(shell git describe --tags --abbrev=0)

ifeq ($(REGISTRY),)
	IMAGE_NAME      := 16psyche/cosmovisor:$(TAG_VERSION)-$(COSMOVISOR_VERSION)
else
	IMAGE_NAME      := $(REGISTRY)/16psyche/cosmovisor:$(TAG_VERSION)-$(COSMOVISOR_VERSION)
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
	@echo "building $(IMAGE_NAME)-$(@:cosmovisor-%=%)"
	$(DOCKER_BUILD) --platform=linux/$(@:cosmovisor-%=%) -t $(IMAGE_NAME)-$(@:cosmovisor-%=%) \
		--build-arg GO_VERSION=$(GO_VERSION) \
		--build-arg COSMOVISOR_VERSION=$(COSMOVISOR_VERSION) \
		--build-arg GO_GETTER_VERSION=$(GO_GETTER_VERSION) \
		-f Dockerfile .

.PHONY: cosmovisor
cosmovisor: $(patsubst %, cosmovisor-%,$(SUBIMAGES))

.PHONY: docker-push-%
docker-push-%:
	docker push $(IMAGE_NAME)-$(@:docker-push-%=%)

.PHONY: docker-push
docker-push: $(patsubst %, docker-push-%,$(SUBIMAGES))

.PHONY: manifest-create
manifest-create:
	@echo "creating manifest $(IMAGE_NAME)"
	docker manifest create $(IMAGE_NAME) $(foreach arch,$(SUBIMAGES), --amend $(IMAGE_NAME)-$(arch))

.PHONY: manifest-push
manifest-push:
	@echo "pushing manifest $(IMAGE_NAME)"
	docker manifest push $(IMAGE_NAME)
