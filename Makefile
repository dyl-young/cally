.PHONY: setup secrets project dev install clean

DEV_DERIVED := build/dev
DEV_APP := $(DEV_DERIVED)/Build/Products/Debug/Cally.app
RELEASE_DERIVED := build/release
RELEASE_APP := $(RELEASE_DERIVED)/Build/Products/Release/Cally.app
INSTALLED_APP := /Applications/Cally.app

setup: secrets project ## First-time bootstrap: generate Secrets.swift then Xcode project

secrets: ## Generate Sources/Generated/Secrets.swift from .env
	@./scripts/generate-secrets.sh

project: secrets ## Generate Cally.xcodeproj from project.yml
	@xcodegen

dev: ## Build Debug and launch from build/dev (kills any running Cally first)
	@pkill -x Cally 2>/dev/null || true
	@xcodebuild -project Cally.xcodeproj -scheme Cally -configuration Debug \
	    -derivedDataPath $(DEV_DERIVED) build -quiet
	@open $(DEV_APP)

install: ## Build Release and install to /Applications (kills any running Cally first)
	@pkill -x Cally 2>/dev/null || true
	@xcodebuild -project Cally.xcodeproj -scheme Cally -configuration Release \
	    -derivedDataPath $(RELEASE_DERIVED) build -quiet
	@ditto $(RELEASE_APP) $(INSTALLED_APP)
	@open $(INSTALLED_APP)

clean: ## Remove generated artefacts
	@rm -rf Cally.xcodeproj DerivedData build Sources/Generated
