UPLOAD_TARGETS := $(addprefix upload-,$(shell ls policy/))
BUILD_TARGETS  := $(addprefix build-,$(shell ls policy/))
SIGN_TARGETS   := $(addprefix sign-,$(shell ls policy/))
VERIFY_TARGETS := $(addprefix verify-,$(shell ls policy/))

# Images used for RPM-level verification (no SELinux enforcement needed).
VERIFY_IMAGE_el8 := rockylinux:8
VERIFY_IMAGE_el9 := quay.io/centos/centos:stream9

$(BUILD_TARGETS):
	docker buildx build \
      --target result --output=. \
      --build-arg TAG=${TAG} \
      --build-arg SCRIPT=build \
      -f Dockerfile.$(@:build-%=%) .

$(SIGN_TARGETS):
	docker buildx build \
      --target result --output=. \
      --build-arg TAG=${TAG} \
      --build-arg SCRIPT=sign \
      -f Dockerfile.$(@:sign-%=%) .

$(UPLOAD_TARGETS):
	docker buildx build \
      --target result --output=. \
      --build-arg TAG=${TAG} \
      --build-arg SCRIPT=upload \
      -f Dockerfile.$(@:upload-%=%) .

$(VERIFY_TARGETS):
	docker run --rm -v $(CURDIR):$(CURDIR) -w $(CURDIR) \
	  $(VERIFY_IMAGE_$(@:verify-%=%)) \
	  bash test/verify-all.sh dist/$(@:verify-%=%)/noarch/vcluster-selinux-*.noarch.rpm

lint:
	docker run --rm -v $(CURDIR):$(CURDIR) -w $(CURDIR) \
	  fedora:45 bash test/verify-lint.sh

clean:
	rm -rf dist/

.PHONY: $(UPLOAD_TARGETS) $(BUILD_TARGETS) $(SIGN_TARGETS) $(VERIFY_TARGETS) lint clean
