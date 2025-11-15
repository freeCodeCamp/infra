.PHONY: help deploy-dashboards update-dashboard delete-dashboard list-dashboards

help:
	@echo "Grafana Dashboard Management"
	@echo ""
	@echo "Available targets:"
	@echo "  deploy-dashboards    - Deploy all dashboards from dashboards/ directory"
	@echo "  update-dashboard     - Update a specific dashboard (usage: make update-dashboard DASHBOARD=api-monitoring)"
	@echo "  delete-dashboard     - Delete a specific dashboard (usage: make delete-dashboard DASHBOARD=api-monitoring)"
	@echo "  list-dashboards      - List all deployed dashboards"
	@echo ""
	@echo "Example:"
	@echo "  make deploy-dashboards"
	@echo "  make update-dashboard DASHBOARD=api-monitoring"

deploy-dashboards:
	@echo "Deploying all dashboards from dashboards/ directory..."
	@for file in dashboards/*.json; do \
		name=$$(basename $$file .json); \
		echo "Creating ConfigMap for $$name..."; \
		kubectl create configmap grafana-dashboard-$$name \
			--from-file=$$file \
			--namespace o11y \
			--dry-run=client -o yaml | \
		kubectl label -f - grafana_dashboard=1 --local --dry-run=client -o yaml | \
		kubectl apply -f -; \
	done
	@echo "✓ All dashboards deployed!"

update-dashboard:
	@if [ -z "$(DASHBOARD)" ]; then \
		echo "Error: DASHBOARD variable not set"; \
		echo "Usage: make update-dashboard DASHBOARD=api-monitoring"; \
		exit 1; \
	fi
	@echo "Updating dashboard: $(DASHBOARD)..."
	@kubectl create configmap grafana-dashboard-$(DASHBOARD) \
		--from-file=dashboards/$(DASHBOARD).json \
		--namespace o11y \
		--dry-run=client -o yaml | \
	kubectl label -f - grafana_dashboard=1 --local --dry-run=client -o yaml | \
	kubectl apply -f -
	@echo "✓ Dashboard $(DASHBOARD) updated! (auto-reloads in ~5 seconds)"

delete-dashboard:
	@if [ -z "$(DASHBOARD)" ]; then \
		echo "Error: DASHBOARD variable not set"; \
		echo "Usage: make delete-dashboard DASHBOARD=api-monitoring"; \
		exit 1; \
	fi
	@echo "Deleting dashboard: $(DASHBOARD)..."
	@kubectl delete configmap grafana-dashboard-$(DASHBOARD) -n o11y
	@echo "✓ Dashboard $(DASHBOARD) deleted!"

list-dashboards:
	@echo "Deployed Grafana Dashboards:"
	@kubectl get configmaps -n o11y -l grafana_dashboard=1 -o custom-columns=NAME:.metadata.name,AGE:.metadata.creationTimestamp
