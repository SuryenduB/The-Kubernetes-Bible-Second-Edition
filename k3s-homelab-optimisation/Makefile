.PHONY: help collect validate verify-backup test-dns test-network dry-run-manifests ansible-audit

help: ## Show this help message
	@echo "K3s Seven-Node Homelab Platform Engineering Automation"
	@echo "Usage: make [target]"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

collect: ## Collect full sanitized cluster and per-node diagnostics
	./scripts/collect-cluster-state.sh
	./scripts/collect-node-state.sh

validate: ## Run comprehensive health and conformance validation suite
	./scripts/validate-cluster.sh

verify-backup: ## Verify local embedded etcd snapshot presence and size
	./scripts/verify-etcd-snapshot.sh

test-dns: ## Run non-destructive DNS resolution and latency tests
	./scripts/validate-dns.sh

test-network: ## Run non-destructive pod-to-pod cross-node network tests
	./scripts/validate-network.sh

dry-run-manifests: ## Validate all Kubernetes manifests with server-side dry run
	kubectl apply --dry-run=server -f kubernetes/storage/default-storageclass-fix.yaml
	kubectl apply --dry-run=server -f kubernetes/monitoring/coredns-ha-patch.yaml
	kubectl apply --dry-run=server -f kubernetes/policies/pod-security-standards-audit.yaml
	kubectl apply --dry-run=server -f kubernetes/tests/smoke-test-workload.yaml

ansible-audit: ## Run non-destructive Ansible node audit
	ansible-playbook -i inventory/generated/cluster-nodes.yaml ansible/playbooks/audit.yaml
