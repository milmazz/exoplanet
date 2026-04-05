.PHONY: setup test format clean shell claude help

help:
	@echo "Development Commands:"
	@echo "  make setup       Install and compile dependencies"
	@echo "  make test        Run all tests"
	@echo "  make format      Format code with mix format"
	@echo "  make clean       Clean build artifacts"
	@echo "  make shell       Open IEx interactive shell"
	@echo "  make claude      Run Claude CLI (args: ARGS=\"--help\")"

setup:
	mix do deps.get + compile

test:
	mix test

format:
	mix format

clean:
	mix clean

shell:
	iex -S mix

claude:
	claude "$(ARGS)"
