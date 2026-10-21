# Verification and release helpers.
.PHONY: check test lint patch

check:            ## every check that can run on this machine
	bash tests/check.sh

test: check

lint:             ## syntax checks only (fast)
	bash -n install.sh
	bash -n uninstall.sh
	node --check files/MenuModel.js

patch:            ## regenerate patches/omarchy-launcher-v2.patch from files/
	@tests/patch/generate.sh
