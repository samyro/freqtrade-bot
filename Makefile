# quant-3rd-lib — local-dev + ops shortcuts
# Mirror of the algo-trader Makefile style. `make` with no args prints help.

VPS_HOST     ?= root@72.62.79.28
NAMESPACE    ?= freqtrade
WEBUI_PORT   ?= 8090
KUBECTL      ?= kubectl
KUBECTL_NS    = $(KUBECTL) -n $(NAMESPACE)
REMOTE_KCTL   = ssh $(VPS_HOST) "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; $(KUBECTL) -n $(NAMESPACE)"

# Default: print help. Tab-indented so make is happy.
.DEFAULT_GOAL := help

.PHONY: help
help: ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\nTargets:\n"} \
	  /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } \
	  /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ WebUI

.PHONY: tunnel
tunnel: ## SSH tunnel to the production WebUI → http://localhost:$(WEBUI_PORT)
	@echo "==> Tunnelling to production freqtrade WebUI..."
	@echo "    Open http://localhost:$(WEBUI_PORT) in your browser"
	@echo "    Press Ctrl+C to close the tunnel"
	ssh -L $(WEBUI_PORT):localhost:$(WEBUI_PORT) $(VPS_HOST)

.PHONY: open
open: ## Open the WebUI in your default browser (assumes `make tunnel` is already running)
	@open http://localhost:$(WEBUI_PORT)

##@ Observability

.PHONY: status
status: ## Show pod + deployment status on the VPS
	$(REMOTE_KCTL) get pods -o wide
	@echo
	$(REMOTE_KCTL) get deploy,svc,pvc

.PHONY: logs
logs: ## Tail the live bot logs from the VPS (Ctrl+C to stop)
	$(REMOTE_KCTL) logs deploy/freqtrade -f --tail=100

.PHONY: events
events: ## Recent k8s events in the freqtrade namespace
	$(REMOTE_KCTL) get events --sort-by=.lastTimestamp | tail -30

##@ Lifecycle

.PHONY: restart
restart: ## Restart the freqtrade pod (picks up new secrets / config changes)
	$(REMOTE_KCTL) rollout restart deployment/freqtrade
	$(REMOTE_KCTL) rollout status deployment/freqtrade --timeout=180s

.PHONY: shell
shell: ## Exec into the freqtrade container (bash)
	$(REMOTE_KCTL) exec -it deploy/freqtrade -- bash

.PHONY: helm-history
helm-history: ## Helm release history for the freqtrade release
	ssh $(VPS_HOST) "export KUBECONFIG=/etc/rancher/k3s/k3s.yaml; helm -n $(NAMESPACE) history freqtrade"

##@ CI / Deploy

.PHONY: deploy
deploy: ## Trigger the GitHub Actions deploy workflow (dry-run, SampleStrategy)
	gh workflow run "CI / Deploy" \
	  --field strategy=SampleStrategy \
	  --field dry_run_override=true

.PHONY: bootstrap
bootstrap: ## Trigger the Bootstrap workflow (rotates k8s secrets)
	gh workflow run "Bootstrap freqtrade VPS"

##@ Local

.PHONY: backtest
backtest: ## Run a local backtest using the SampleStrategy (last 90 days, ETH/USDT)
	docker run --rm -it \
	  -v "$$(pwd)/user_data:/freqtrade/user_data" \
	  freqtradeorg/freqtrade:stable \
	  backtesting \
	    --strategy SampleStrategy \
	    --config /freqtrade/user_data/config.json \
	    --timerange $$(date -v -90d +%Y%m%d 2>/dev/null || date -d "90 days ago" +%Y%m%d)-

.PHONY: download-data
download-data: ## Download 90d of ETH/USDT 5m bars from Kraken into user_data/data/
	docker run --rm -it \
	  -v "$$(pwd)/user_data:/freqtrade/user_data" \
	  freqtradeorg/freqtrade:stable \
	  download-data \
	    --exchange kraken \
	    --pairs ETH/USDT \
	    --timeframes 5m \
	    --days 90

##@ Strategy management

# Default source: the freqtrade-strategies repo's `berlinguyinca/` folder.
# Override with `SRC=https://...` for strategies in other folders.
STRATEGY_SRC ?= https://raw.githubusercontent.com/freqtrade/freqtrade-strategies/main/user_data/strategies/berlinguyinca/$(NAME).py

.PHONY: strategy
strategy: ## Switch to a community strategy. Usage: make strategy NAME=BbandRsi
	@if [ -z "$(NAME)" ]; then \
		echo ""; \
		echo "Error: NAME is required."; \
		echo "  Usage:  make strategy NAME=BbandRsi"; \
		echo "  Override URL:  make strategy NAME=Foo SRC=https://example.com/Foo.py"; \
		echo ""; \
		exit 1; \
	fi
	@echo "==> Downloading $(NAME) from $(STRATEGY_SRC)"
	@curl -fsSL -o user_data/strategies/$(NAME).py "$(STRATEGY_SRC)" \
	  || { echo ""; echo "Download failed. The strategy may be in a different subfolder."; \
	       echo "Browse https://github.com/freqtrade/freqtrade-strategies and override:"; \
	       echo "  make strategy NAME=$(NAME) SRC=<raw-github-url>"; \
	       rm -f user_data/strategies/$(NAME).py; exit 1; }
	@echo "==> Verifying class name '$(NAME)' exists in the file"
	@if ! grep -qE "^class $(NAME)\b" user_data/strategies/$(NAME).py; then \
		echo ""; \
		echo "WARN: 'class $(NAME)' not found in the downloaded file. Classes present:"; \
		grep -E "^class " user_data/strategies/$(NAME).py || true; \
		echo ""; \
		echo "Either rename the file to match the class, or update values.yaml manually."; \
		exit 1; \
	fi
	@echo "==> Updating helm/freqtrade/values.yaml -> strategy: $(NAME)"
	@sed -i.bak 's/^strategy: .*/strategy: $(NAME)/' helm/freqtrade/values.yaml && rm -f helm/freqtrade/values.yaml.bak
	@grep '^strategy:' helm/freqtrade/values.yaml
	@echo ""
	@echo "==> Committing + pushing — CI will auto-deploy in ~3 min"
	@git add user_data/strategies/$(NAME).py helm/freqtrade/values.yaml
	@git commit -m "switch to $(NAME) strategy"
	@git push -u origin HEAD
	@echo ""
	@echo "Watch the deploy: gh run watch  (or open the Actions tab)"
	@echo "After ~3 min:    make logs   # confirm 'Strategy: $(NAME)'"

.PHONY: strategy-list
strategy-list: ## Show all strategy files currently in the repo
	@echo "Strategies in user_data/strategies/:"
	@for f in user_data/strategies/*.py; do \
		[ -f "$$f" ] || continue; \
		cls=$$(grep -E "^class " "$$f" | head -1 | sed 's/class \([A-Za-z0-9_]*\).*/\1/'); \
		echo "  $$(basename $$f .py)    class=$$cls"; \
	done
	@echo ""
	@echo "Currently deployed:"
	@grep '^strategy:' helm/freqtrade/values.yaml
