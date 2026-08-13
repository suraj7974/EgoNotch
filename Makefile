APP      := EgoNotch
CONFIG   := Debug
DERIVED  := build
APP_PATH := $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app

.PHONY: bootstrap generate build run stop clean reset-tcc

bootstrap:            ## one-time setup after clone
	command -v xcodegen >/dev/null || brew install xcodegen
	xcodegen generate

generate:             ## regen project (no-op if project.yml unchanged)
	xcodegen generate --use-cache

build: generate
	xcodebuild -project $(APP).xcodeproj -scheme $(APP) \
	  -configuration $(CONFIG) -derivedDataPath $(DERIVED) build

run: build
	-pkill -x $(APP)
	open $(APP_PATH)

stop:
	-pkill -x $(APP)

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj

reset-tcc:            ## recovery only; grants normally survive rebuilds
	-tccutil reset Accessibility com.suraj.$(APP)
