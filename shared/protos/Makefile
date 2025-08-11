.PHONY: help
help: ## Show this help message
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

.PHONY: deps
deps: ## Install dependencies for proto generation
	@echo "Installing protoc dependencies..."
	go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
	go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest
	pip install grpcio-tools

.PHONY: generate
generate: generate-go generate-python ## Generate code for all languages
	@echo "Code generation complete!"

.PHONY: generate-go
generate-go: ## Generate Go code from proto files
	@echo "Generating Go code..."
	@mkdir -p generated/go/common generated/go/services
	@for file in common/*.proto; do \
		protoc --go_out=generated/go --go_opt=paths=source_relative \
			   --go-grpc_out=generated/go --go-grpc_opt=paths=source_relative \
			   -I. -I/usr/local/include \
			   $$file; \
	done
	@for file in services/*.proto; do \
		if [ -f "$$file" ]; then \
			protoc --go_out=generated/go --go_opt=paths=source_relative \
				   --go-grpc_out=generated/go --go-grpc_opt=paths=source_relative \
				   -I. -I/usr/local/include \
				   $$file; \
		fi \
	done
	@echo "Go code generation complete!"

.PHONY: generate-python
generate-python: ## Generate Python code from proto files
	@echo "Generating Python code..."
	@mkdir -p generated/python/pyairtable_protos/common generated/python/pyairtable_protos/services
	@touch generated/python/pyairtable_protos/__init__.py
	@touch generated/python/pyairtable_protos/common/__init__.py
	@touch generated/python/pyairtable_protos/services/__init__.py
	@for file in common/*.proto; do \
		python -m grpc_tools.protoc \
			-I. -I/usr/local/include \
			--python_out=generated/python \
			--grpc_python_out=generated/python \
			$$file; \
	done
	@for file in services/*.proto; do \
		if [ -f "$$file" ]; then \
			python -m grpc_tools.protoc \
				-I. -I/usr/local/include \
				--python_out=generated/python \
				--grpc_python_out=generated/python \
				$$file; \
		fi \
	done
	@echo "Python code generation complete!"

.PHONY: clean
clean: ## Clean generated code
	rm -rf generated/

.PHONY: validate
validate: ## Validate proto files
	@echo "Validating proto files..."
	@for file in common/*.proto services/*.proto; do \
		if [ -f "$$file" ]; then \
			protoc --proto_path=. --proto_path=/usr/local/include --descriptor_set_out=/dev/null $$file && \
			echo "✓ $$file" || echo "✗ $$file"; \
		fi \
	done

.PHONY: init
init: ## Initialize the repository
	@mkdir -p common services scripts generated/go generated/python
	@echo "Repository initialized!"

.PHONY: test-generation
test-generation: clean generate ## Test code generation
	@echo "Testing code generation..."
	@if [ -d "generated/go" ] && [ -d "generated/python" ]; then \
		echo "✓ Code generation successful!"; \
	else \
		echo "✗ Code generation failed!"; \
		exit 1; \
	fi