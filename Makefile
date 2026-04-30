.PHONY: setup secrets project clean

setup: secrets project ## First-time bootstrap: generate Secrets.swift then Xcode project

secrets: ## Generate Sources/Generated/Secrets.swift from .env
	@./scripts/generate-secrets.sh

project: secrets ## Generate Cally.xcodeproj from project.yml
	@xcodegen

clean: ## Remove generated artefacts
	@rm -rf Cally.xcodeproj DerivedData build Sources/Generated
