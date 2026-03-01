# -------------------------------
# Variables
# -------------------------------
CLUSTER_NAME := dockercluster
ARGO_NAMESPACE := argocd
DEV_NAMESPACE := dev
ARGO_PORT := 2746
APP_PORT := 8888
K3D := k3d
ARGOCD := argocd
KUBECTL := kubectl

# Paths to your k8s YAMLs
DEV_DEPLOYMENT := ./deployment.yaml
DEV_SERVICE := k8s/dev-service.yaml

# -------------------------------
# Phony targets
# -------------------------------
.PHONY: all setup create check-k3d create-namespaces install-argo deploy-app delete shell info \
	port-forward port-forward-app echo-password

all: setup

# -------------------------------
# Full setup
# -------------------------------
setup: check-k3d create create-namespaces install-argo deploy-app
	@echo "🌟 Setup complete!"
	@echo "👉 Argo UI: $(KUBECTL) -n $(ARGO_NAMESPACE) port-forward svc/argocd-server $(ARGO_PORT):443"
	@echo "👉 App: $(KUBECTL) -n $(DEV_NAMESPACE) port-forward svc/wil-playground $(APP_PORT):8888"

# -------------------------------
# Check k3d installation
# -------------------------------
check-k3d:
	@if ! command -v $(K3D) >/dev/null 2>&1; then \
		echo "🔧 k3d not found. Installing..."; \
		curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash; \
	else \
		echo "✅ k3d already installed"; \
	fi

	@if ! command -v $(ARGOCD) >/dev/null 2>&1; then \
		echo "🔧 argocd CLI not found. Installing..."; \
		curl -sSL -o argocd \
		https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64; \
		chmod +x argocd; \
		sudo mv argocd /usr/local/bin/; \
	else \
		echo "✅ argocd CLI already installed"; \
	fi

# -------------------------------
# Create K3s cluster
# -------------------------------
create: check-k3d
	@echo "🚀 Creating K3s cluster: $(CLUSTER_NAME)"
	-$(K3D) cluster create $(CLUSTER_NAME) --agents 1 || true

# -------------------------------
# Create Namespaces (idempotent)
# -------------------------------
create-namespaces:
	@echo "📂 Creating namespaces..."
	$(KUBECTL) create namespace $(ARGO_NAMESPACE) --dry-run=client -o yaml | $(KUBECTL) apply -f -
	$(KUBECTL) create namespace $(DEV_NAMESPACE) --dry-run=client -o yaml | $(KUBECTL) apply -f -

# -------------------------------
# Install ArgoCD
# -------------------------------
install-argo:
	@echo "🌟 Installing Argo CD in namespace $(ARGO_NAMESPACE)"
	$(KUBECTL) apply -n $(ARGO_NAMESPACE) -f \
	https://raw.githubusercontent.com/argoproj/argo-cd/v2.7.12/manifests/install.yaml

# -------------------------------
# Deploy your app
# -------------------------------
deploy-app:
	@echo "🚀 Deploying app to namespace $(DEV_NAMESPACE)"
	$(KUBECTL) apply -f $(DEV_DEPLOYMENT) -n $(DEV_NAMESPACE)
# 	$(KUBECTL) apply -f $(DEV_SERVICE) -n $(DEV_NAMESPACE)

# -------------------------------
# Delete cluster
# -------------------------------
delete:
	@echo "🧹 Deleting K3s cluster: $(CLUSTER_NAME)"
	-$(K3D) cluster delete $(CLUSTER_NAME)

# -------------------------------
# Shell into K3s server container
# -------------------------------
shell:
	@echo "🔗 Opening shell to K3s server container"
	docker exec -it k3d-$(CLUSTER_NAME)-server-0 sh

# -------------------------------
# Cluster info
# -------------------------------
info:
	@echo "ℹ Cluster nodes:"
	$(K3D) cluster list
	$(KUBECTL) get nodes -o wide
	$(KUBECTL) get pods -n $(ARGO_NAMESPACE) -w

# -------------------------------
# Port forwarding
# -------------------------------
port-forward:
	$(KUBECTL) -n $(ARGO_NAMESPACE) port-forward svc/argocd-server $(ARGO_PORT):443

port-forward-app:
	$(KUBECTL) -n $(DEV_NAMESPACE) port-forward svc/wil-playground $(APP_PORT):8888

# -------------------------------
# Show ArgoCD admin password
# -------------------------------
echo-password:
	$(KUBECTL) -n $(ARGO_NAMESPACE) get secret argocd-initial-admin-secret \
	-o jsonpath="{.data.password}" | base64 -d
	@echo


# -------------------------------
# provision Github repo
# -------------------------------
argocd-setup:
	@echo "🔐 Waiting for ArgoCD server to be ready..."
	@sleep 5  # optional initial wait
	@until curl -k https://localhost:2746 | grep -q "Argo CD"; do \
		echo "⏳ ArgoCD not ready yet... retrying in 3s"; \
		sleep 3; \
	done
	@echo "🔐 Logging into ArgoCD..."
	@ARGO_PASSWORD=$$($(KUBECTL) -n $(ARGO_NAMESPACE) get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d); \
	echo "➡ Using password: $$ARGO_PASSWORD"; \
	argocd login localhost:$(ARGO_PORT) --username admin --password "$$ARGO_PASSWORD" --insecure --grpc-web
	@echo "📦 Adding Git repo..."
	@argocd repo add git@github.com:Robin-Lenz/rpodackIoT.git --upsert
	@echo "🚀 Creating ArgoCD app..."
	@argocd app create dev-app \
	  --repo git@github.com:Robin-Lenz/rpodackIoT.git \
	  --path k8s \
	  --dest-server https://kubernetes.default.svc \
	  --dest-namespace dev \
	  --sync-policy automated \
	  --auto-prune \
	  --self-heal \
	  --upsert
	@echo "✅ ArgoCD setup complete!"


# CLUSTER_NAME := dockercluster
# ARGO_NAMESPACE := argocd
#
# .PHONY: setup create install-argo delete shell info
#
# all: setup
#
# # ✅ Full setup: k3d + cluster + Argo
# setup: create install-argo
# 	@echo "🌟 Setup complete!"
# 	@echo "👉 Access Argo UI:"
# 	@echo "kubectl -n $(ARGO_NAMESPACE) port-forward svc/argo-server 2746:2746"
# 	@echo "Then open http://localhost:2746 in your browser"
#
# # Install k3d if not found
# check-k3d:
# 	@if ! command -v k3d >/dev/null 2>&1; then \
# 		echo "🔧 k3d not found. Installing..."; \
# 		curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash; \
# 	else \
# 		echo "✅ k3d is already installed"; \
# 	fi
#
# # Create a K3s cluster using k3d
# create: check-k3d
# 	@echo "🚀 Creating K3s cluster: $(CLUSTER_NAME)"
# 	-k3d cluster create $(CLUSTER_NAME) --agents 1 || true
#
# # Deploy Argo cd
# install-argo:
# 	@echo "🌟 Installing Argo cd in namespace $(ARGO_NAMESPACE)"
# 	-kubectl create namespace $(ARGO_NAMESPACE) || true
# 	-kubectl apply -n argocd -f \
# 	https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
# # Delete cluster
# delete:
# 	@echo "🧹 Deleting K3s cluster: $(CLUSTER_NAME)"
# 	-k3d cluster delete $(CLUSTER_NAME)
#
# # Open a shell in the K3s server container
# shell:
# 	@echo "🔗 Opening shell to K3s server container"
# 	docker exec -it k3d-$(CLUSTER_NAME)-server-0 sh
#
# # Cluster info
# info:
# 	@echo "ℹ Cluster nodes:"
# 	k3d cluster list
# 	kubectl get nodes -o wide
# 	kubectl get pods -n argo -w
#
# create-namespaces:
# 	kubectl create namespace $(ARGO_NAMESPACE) --dry-run=client -o yaml | kubectl apply -f -
# 	kubectl create namespace dev --dry-run=client -o yaml | kubectl apply -f -
#
# port-forward:
# 	kubectl -n argocd port-forward svc/argocd-server 8080:443
#
# port-forward-app:
# 	kubectl -n dev port-forward svc/wil-playground 8888:8888
# # after every change holes need to be punched again -- both
#
# echo-password:
# 	kubectl -n argocd get secret argocd-initial-admin-secret \
# 	-o jsonpath="{.data.password}" | base64 -d
# 	echo
#
# # check the app curl http://localhost:8888
