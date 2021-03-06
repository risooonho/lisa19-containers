SHELL = bash -e
REVISION ?= 1
VERSION ?= $(shell date +%y.%m.$(REVISION))
IMG := thedoh/lisa19
REGISTRY ?= docker.io
ARCHES ?= amd64 arm64
TAG_LATEST ?= true

INSECURE ?=

default: all
all: validate-options clean docker-build docker-multiarch docker-push $(PULL_BINARY)

include app.mk
include verbose.mk
include functions.mk
include validate.mk


.PHONY: docker-build
docker-build:
	$(AT)for a in $(ARCHES); do \
		echo "[docker-build] Docker build $(REGISTRY)/$(IMG):$$a-$(VERSION) with GOARCH=$$a" ;\
		docker build --platform=linux/$$a --build-arg=GOARCH=$$a -t $(REGISTRY)/$(IMG):$$a-$(VERSION) . $(redirect) ;\
		$(call set_image_arch,$(REGISTRY)/$(IMG):$$a-$(VERSION),$$a) ;\
		if [[ $(TAG_LATEST) == "true" ]]; then \
			echo "[docker-build] Tagging $$a-latest" ;\
			docker tag $(REGISTRY)/$(IMG):$$a-$(VERSION) $(REGISTRY)/$(IMG):$$a-latest $(redirect) ;\
		fi ;\
	done

.PHONY: docker-multiarch
docker-multiarch: docker-build
	$(AT)arches= ;\
	for a in $(ARCHES); do \
		echo "[docker-multiarch] Docker pushing 'intermediate' arch=$$a to $(REGISTRY)" ;\
		arches="$$arches $(REGISTRY)/$(IMG):$$a-$(VERSION)" ;\
		docker push $(REGISTRY)/$(IMG):$$a-$(VERSION) $(redirect) 1>/dev/null ;\
	done ;\
	echo "[docker-multiarch] Creating manifest with docker manifest create $(INSECURE) $(REGISTRY)/$(IMG):$(VERSION) $$arches" ;\
	docker manifest create $(INSECURE) $(REGISTRY)/$(IMG):$(VERSION) $$arches $(redirect) ;\
	if [[ $(TAG_LATEST) == "true" ]]; then \
		echo "[docker-multiarch]: Creating 'latest' manifest" ;\
		docker manifest create $(INSECURE) $(REGISTRY)/$(IMG):latest $$arches $(redirect) ;\
	fi ;\
	for a in $(ARCHES); do \
		echo "[docker-multiarch] Annotating $(REGISTRY)/$(IMG):$(VERSION) with $(REGISTRY)/$(IMG):$$a-$(VERSION)" --os linux --arch $$a ;\
		docker manifest annotate $(REGISTRY)/$(IMG):$(VERSION) $(REGISTRY)/$(IMG):$$a-$(VERSION) --os linux --arch $$a $(redirect) ;\
		if [[ $(TAG_LATEST) == "true" ]]; then \
			docker manifest annotate $(REGISTRY)/$(IMG):latest $(REGISTRY)/$(IMG):$$a-$(VERSION) --os linux --arch $$a $(redirect) ;\
		fi ;\
	done

.PHONY: docker-push
docker-push: docker-build docker-multiarch
	$(AT)echo "[docker-push] Pushing $(REGISTRY)/$(IMG):$(VERSION) to $(REGISTRY)" ;\
	docker manifest push $(INSECURE) $(REGISTRY)/$(IMG):$(VERSION) $(redirect) ;\
	if [[ $(TAG_LATEST) == "true" ]]; then \
		docker manifest push $(INSECURE) $(REGISTRY)/$(IMG):latest $(redirect) ;\
	fi

.PHONY: clean
clean: pull-app-clean clean-fetches
	$(AT)for a in $(ARCHES); do \
		echo "[clean] Local image delete for $(REGISTRY)/$(IMG):$$a-$(VERSION) and $(REGISTRY)/$(IMG):$$a-latest" ;\
		docker rmi --force $(REGISTRY)/$(IMG):$$a-$(VERSION) &>/dev/null || true ;\
		docker rmi --force $(REGISTRY)/$(IMG):$$a-latest &>/dev/null || true ;\
	done ;\
	echo "[clean] Cleaning multiarch $(REGISTRY)/$(IMG):latest and $(REGISTRY)/$(IMG):$(VERSION)" ;\
	docker rmi --force $(REGISTRY)/$(IMG):latest &>/dev/null || true ;\
	docker rmi --force $(REGISTRY)/$(IMG):$(VERSION) &>/dev/null || true ;\
	rm -vrf ~/.docker/manifests/$(shell echo $(REGISTRY)/$(IMG) | tr '/' '_' | tr ':' '-')-$(VERSION) $(redirect) || true ;\
	rm -vrf ~/.docker/manifests/$(shell echo $(REGISTRY)/$(IMG) | tr '/' '_' | tr ':' '-')-latest $(redirect) || true ;\

