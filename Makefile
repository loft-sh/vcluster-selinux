TAG ?= $(shell git describe --tags --always --dirty 2>/dev/null || echo "v0.0.dev.0")
DISTROS := $(notdir $(wildcard policy/*))

.PHONY: all clean $(addprefix build-,$(DISTROS)) $(addprefix sign-,$(DISTROS))

all: $(addprefix build-,$(DISTROS))

define DISTRO_TARGETS
build-$(1):
	docker buildx build \
		--build-arg TAG=$(TAG) \
		--build-arg SCRIPT=build \
		-f Dockerfile.$(1) \
		-o type=local,dest=./dist/$(1) \
		.

sign-$(1):
	docker buildx build \
		--build-arg TAG=$(TAG) \
		--build-arg SCRIPT=sign \
		--secret id=private_key,env=PRIVATE_KEY \
		--secret id=private_key_pass,env=PRIVATE_KEY_PASS_PHRASE \
		-f Dockerfile.$(1) \
		-o type=local,dest=./dist/$(1) \
		.
endef

$(foreach distro,$(DISTROS),$(eval $(call DISTRO_TARGETS,$(distro))))

clean:
	rm -rf dist/
