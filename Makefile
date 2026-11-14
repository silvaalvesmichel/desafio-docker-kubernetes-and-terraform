# Shortcuts for the cluster flow. The database password comes from TF_VAR_db_password
# or from infra/terraform/terraform.tfvars.

TF         := terraform -chdir=infra/terraform
KUBECFG    := $(CURDIR)/infra/terraform/.kube/config
HOST       ?= mural.localtest.me

.PHONY: up down status load

up: ## Create the cluster and deploy the Mural
	$(TF) init -input=false
	$(TF) apply -auto-approve

down: ## Remove everything
	$(TF) destroy -auto-approve

status: ## Show what is running in the mural namespace
	kubectl --kubeconfig $(KUBECFG) -n mural get pods,svc,ingress,hpa,pvc,job

load: ## Put load on the API (watch "make status" scale it)
	docker run --rm --network host --add-host $(HOST):127.0.0.1 \
	  -v $(CURDIR)/infra/k6:/scripts:ro -e BASE_URL=http://$(HOST) \
	  grafana/k6 run /scripts/load.js
