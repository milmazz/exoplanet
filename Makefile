.PHONY: dev:build dev:up dev:stop dev:shell dev:claude help

COMPOSE = docker compose -f .devcontainer/docker-compose.yml

help:
	@echo "Development Commands:"
	@echo "  make dev:build   Build the dev container"
	@echo "  make dev:up      Start the dev container"
	@echo "  make dev:stop    Stop the dev container"
	@echo "  make dev:shell   Open a shell inside the dev container"
	@echo "  make dev:claude  Start Claude CLI (--dangerously-skip-permissions)"

dev\:build:
	$(COMPOSE) build

dev\:up:
	mkdir -p $(HOME)/.local/share/fish
	$(COMPOSE) up -d

dev\:stop:
	$(COMPOSE) stop

dev\:shell:
	$(COMPOSE) exec exoplanet /bin/bash

dev\:claude:
	$(COMPOSE) exec exoplanet claude --dangerously-skip-permissions
