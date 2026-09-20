SHELL := /usr/bin/env bash

.PHONY: setup inventory preflight cluster recover-cni cilium demo deploy validate proof upgrade reset clean-proof

setup:
	./scripts/00_setup_kubespray.sh

inventory:
	./scripts/01_generate_inventory.sh

preflight: setup inventory
	cd state/kubespray && ../venv/bin/ansible -i ../inventory/inventory.ini all --become -m ping

cluster:
	./scripts/02_deploy_cluster.sh

recover-cni:
	cd state/kubespray && ../venv/bin/ansible-playbook -i ../inventory/inventory.ini cluster.yml --become --tags network

cilium:
	./scripts/03_configure_cilium.sh

demo:
	./scripts/04_deploy_demo.sh

validate:
	./scripts/05_validate.sh

proof:
	./scripts/06_capture_proof.sh

deploy: preflight cluster cilium demo validate

upgrade:
	cd state/kubespray && ../venv/bin/ansible-playbook -i ../inventory/inventory.ini upgrade-cluster.yml --become

reset:
	cd state/kubespray && ../venv/bin/ansible-playbook -i ../inventory/inventory.ini reset.yml --become

clean-proof:
	rm -f proof/*.txt proof/*.log
