DOCKERHUB_IMAGE := teochenglim/laya
GHCR_IMAGE      := ghcr.io/teochenglim/laya
MODELS          := english multilingual typed-decisions
BACKENDS        := cpu gpu
LATEST_MODEL    := english
PORT            := 8080
CONTAINER       := laya-play
MODEL           ?= $(LATEST_MODEL)
BACKEND         ?= cpu
TAG             := $(MODEL)-$(BACKEND)
# Disabled on push: building then pushing separately round-trips through the
# local containerd content store, which on containerd-snapshotter Docker
# (e.g. colima) can drop an attestation-manifest blob and fail the push with
# "content digest ... not found". A single `buildx build --push` sidesteps it.
BUILDX_PUSH_FLAGS := --provenance=false --sbom=false

.PHONY: help build build-all push push-all push-aliases \
        ghcr-build ghcr-build-all ghcr-push ghcr-push-all ghcr-push-aliases \
        run test stop clean

help:
	@echo "Local dev:"
	@echo "  make dev            uv run python laya_init.py"
	@echo "  make serve          uv run laya-serve (reads .env for HF_TOKEN)"
	@echo ""
	@echo "Docker Hub ($(DOCKERHUB_IMAGE)):"
	@echo "  make build   MODEL=... BACKEND=cpu|gpu   build one (model, backend) variant"
	@echo "  make build-all                           build all model x backend variants"
	@echo "  make push    MODEL=... BACKEND=cpu|gpu   build+push one variant, tag <model>-<backend>"
	@echo "  make push-all                            build+push every variant"
	@echo "  make push-aliases                        point :latest/:cpu/:gpu at $(LATEST_MODEL)"
	@echo ""
	@echo "GHCR ($(GHCR_IMAGE)):"
	@echo "  make ghcr-build / ghcr-build-all / ghcr-push / ghcr-push-all / ghcr-push-aliases"
	@echo ""
	@echo "Run + test:"
	@echo "  make run  MODEL=... BACKEND=cpu|gpu   run image locally on :$(PORT)"
	@echo "  make test                             curl /health and /v1/systemone"
	@echo "  make stop                             stop and remove the local test container"
	@echo "  make clean                            remove local Docker Hub + GHCR images for this project"

dev:
	uv run python laya_init.py

serve:
	uv run laya-serve

# ---- Docker Hub ----

build:
	docker build --build-arg LAYA_MODEL=$(MODEL) --build-arg BACKEND=$(BACKEND) --secret id=hf_token,env=HF_TOKEN -t $(DOCKERHUB_IMAGE):$(TAG) .

build-all:
	@for m in $(MODELS); do for b in $(BACKENDS); do $(MAKE) build MODEL=$$m BACKEND=$$b; done; done

push:
	docker buildx build $(BUILDX_PUSH_FLAGS) --build-arg LAYA_MODEL=$(MODEL) --build-arg BACKEND=$(BACKEND) --secret id=hf_token,env=HF_TOKEN -t $(DOCKERHUB_IMAGE):$(TAG) --push .

push-all:
	@for m in $(MODELS); do for b in $(BACKENDS); do $(MAKE) push MODEL=$$m BACKEND=$$b; done; done

# Registry-side retags via imagetools: no local image needed (push doesn't load one).
push-aliases:
	docker buildx imagetools create -t $(DOCKERHUB_IMAGE):latest $(DOCKERHUB_IMAGE):$(LATEST_MODEL)-cpu
	docker buildx imagetools create -t $(DOCKERHUB_IMAGE):cpu    $(DOCKERHUB_IMAGE):$(LATEST_MODEL)-cpu
	docker buildx imagetools create -t $(DOCKERHUB_IMAGE):gpu    $(DOCKERHUB_IMAGE):$(LATEST_MODEL)-gpu

# ---- GHCR ----

ghcr-build:
	docker build --build-arg LAYA_MODEL=$(MODEL) --build-arg BACKEND=$(BACKEND) --secret id=hf_token,env=HF_TOKEN -t $(GHCR_IMAGE):$(TAG) .

ghcr-build-all:
	@for m in $(MODELS); do for b in $(BACKENDS); do $(MAKE) ghcr-build MODEL=$$m BACKEND=$$b; done; done

ghcr-push:
	docker buildx build $(BUILDX_PUSH_FLAGS) --build-arg LAYA_MODEL=$(MODEL) --build-arg BACKEND=$(BACKEND) --secret id=hf_token,env=HF_TOKEN -t $(GHCR_IMAGE):$(TAG) --push .

ghcr-push-all:
	@for m in $(MODELS); do for b in $(BACKENDS); do $(MAKE) ghcr-push MODEL=$$m BACKEND=$$b; done; done

ghcr-push-aliases:
	docker buildx imagetools create -t $(GHCR_IMAGE):latest $(GHCR_IMAGE):$(LATEST_MODEL)-cpu
	docker buildx imagetools create -t $(GHCR_IMAGE):cpu    $(GHCR_IMAGE):$(LATEST_MODEL)-cpu
	docker buildx imagetools create -t $(GHCR_IMAGE):gpu    $(GHCR_IMAGE):$(LATEST_MODEL)-gpu

# ---- Run + test ----

run:
	docker rm -f $(CONTAINER) >/dev/null 2>&1 || true
	docker run -d --name $(CONTAINER) -p $(PORT):8080 $(DOCKERHUB_IMAGE):$(TAG)

test:
	curl -sf http://localhost:$(PORT)/health && echo
	curl -s http://localhost:$(PORT)/v1/systemone \
		-H 'Content-Type: application/json' \
		-d '{ \
			"state": {"message": "I was charged twice for invoice 4411. Please refund me today."}, \
			"questions": { \
				"route": {"type": "choice", "instructions": "Where should this ticket go?", \
					"criteria": {"billing": "payments, refunds, invoices", "bug": "the product is broken", "account": "login or access"}}, \
				"urgency": {"type": "score", "instructions": "How urgent is this message?", \
					"criteria": ["routine, no rush", "today", "urgent", "critical, about to churn"]}, \
				"escalate": {"type": "noul", "instructions": "Escalate to a human immediately?"} \
			} \
		}' | python3 -m json.tool

stop:
	docker rm -f $(CONTAINER) >/dev/null 2>&1 || true

clean:
	-docker rmi $(foreach m,$(MODELS),$(foreach b,$(BACKENDS),$(DOCKERHUB_IMAGE):$(m)-$(b))) $(DOCKERHUB_IMAGE):latest $(DOCKERHUB_IMAGE):cpu $(DOCKERHUB_IMAGE):gpu 2>/dev/null
	-docker rmi $(foreach m,$(MODELS),$(foreach b,$(BACKENDS),$(GHCR_IMAGE):$(m)-$(b))) $(GHCR_IMAGE):latest $(GHCR_IMAGE):cpu $(GHCR_IMAGE):gpu 2>/dev/null
