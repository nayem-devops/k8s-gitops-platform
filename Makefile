SHELL := /bin/bash

APP_NAME        ?= bookify-client
APP_NAMESPACE   ?= bookify
APP_SRC         ?= bookify/bookify-client
APP_REPO        ?= https://github.com/nayem9b/bookify-client.git
APP_VALUES      ?= bookify/bookify-values.yaml
TAG             ?= 0.0.1

MON_RELEASE     ?= monitoring
MON_NAMESPACE   ?= monitoring
MON_CHART       ?= oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack
MON_VERSION     ?= 92.3.0

HOSTS           := bookify.local grafana.local prometheus.local alertmanager.local

.PHONY: help all cluster clone values image app monitoring hosts grafana-password status vm app-down monitoring-down down

help:
	@echo "make all               cluster + app + monitoring + hosts, start to finish"
	@echo "make cluster           start minikube and enable ingress"
	@echo "make clone             clone bookify-client into $(APP_SRC)"
	@echo "make values            create $(APP_VALUES) with placeholders if missing"
	@echo "make image TAG=x.y.z   build the client image inside minikube"
	@echo "make app TAG=x.y.z     install or upgrade the bookify-client chart"
	@echo "make monitoring        install or upgrade kube-prometheus-stack"
	@echo "make hosts             point the *.local hosts at minikube (sudo)"
	@echo "make grafana-password  print the Grafana admin password"
	@echo "make status            show what is running"
	@echo "make vm                configure nginx on the VM with ansible"
	@echo "make app-down          uninstall bookify-client"
	@echo "make monitoring-down   uninstall the monitoring stack"
	@echo "make down              stop minikube"

all: cluster image app monitoring hosts status

cluster:
	@minikube status >/dev/null 2>&1 || minikube start --memory=6g --cpus=monitoring-grafana4
	minikube addons enable ingress
	kubectl -n ingress-nginx wait --for=condition=ready pod \
		-l app.kubernetes.io/component=controller --timeout=180s

clone:
	@test -d $(APP_SRC) || git clone $(APP_REPO) $(APP_SRC)

values:
	@test -f $(APP_VALUES) || { \
		mkdir -p $(dir $(APP_VALUES)); \
		printf '%s\n' \
			'env:' \
			'  REACT_APP_AUTH_DOMAIN: your-app.firebaseapp.com' \
			'  REACT_APP_PROJECT_ID: your-app' \
			'  REACT_APP_STORAGE_BUCKET: your-app.appspot.com' \
			'  REACT_APP_MESSAGING_SENDER_ID: "1234567890"' \
			'  REACT_APP_APP_ID: "1:1234567890:web:abc123"' \
			'' \
			'secretEnv:' \
			'  REACT_APP_API_KEY: your-firebase-api-key' > $(APP_VALUES); \
		echo "created $(APP_VALUES), put your real Firebase values in it"; \
	}

image: clone
	minikube image build -t $(APP_NAME):$(TAG) $(APP_SRC)

app: values
	helm upgrade --install $(APP_NAME) ./k8s \
		-n $(APP_NAMESPACE) --create-namespace \
		-f $(APP_VALUES) --set image.tag=$(TAG) \
		--wait --timeout 5m

monitoring:
	helm upgrade --install $(MON_RELEASE) $(MON_CHART) --version $(MON_VERSION) \
		-n $(MON_NAMESPACE) --create-namespace \
		-f monitoring/values.yaml \
		--wait --timeout 10m

hosts:
	@ip=$$(minikube ip); \
	sudo sed -i -E '/\s(bookify|grafana|prometheus|alertmanager)\.local(\s|$$)/d' /etc/hosts; \
	echo "$$ip $(HOSTS)" | sudo tee -a /etc/hosts >/dev/null; \
	echo "$$ip -> $(HOSTS)"

grafana-password:
	@kubectl -n $(MON_NAMESPACE) get secret $(MON_RELEASE)-grafana \
		-o jsonpath='{.data.admin-password}' | base64 -d; echo

status:
	@helm list -A
	@echo
	@kubectl -n $(APP_NAMESPACE) get pods,svc,ingress 2>/dev/null || true
	@echo
	@kubectl -n $(MON_NAMESPACE) get pods,ingress 2>/dev/null || true

vm:
	ansible-playbook -i nginx/inventory.ini nginx/nginx.yml

app-down:
	helm uninstall $(APP_NAME) -n $(APP_NAMESPACE)

monitoring-down:
	helm uninstall $(MON_RELEASE) -n $(MON_NAMESPACE)

down:
	minikube stop
