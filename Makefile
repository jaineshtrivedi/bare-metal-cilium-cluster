SHELL := /usr/bin/env bash

.PHONY: prepare init join cilium demo validate proof clean-proof

prepare:
	./scripts/00_prepare_hosts.sh

init:
	./scripts/01_bootstrap_first_control_plane.sh

join:
	./scripts/02_join_remaining_nodes.sh

cilium:
	./scripts/03_install_cilium.sh

demo:
	./scripts/04_deploy_demo.sh

validate:
	./scripts/05_validate.sh

proof:
	./scripts/06_capture_proof.sh

clean-proof:
	rm -f proof/*.txt proof/*.log

