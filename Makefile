APP      := EgoNotch
CONFIG   := Debug
DERIVED  := build
APP_PATH := $(DERIVED)/Build/Products/$(CONFIG)/$(APP).app
ICONSET  := EgoNotch/Resources/Assets.xcassets/AppIcon.appiconset

.PHONY: bootstrap generate build run install stop clean reset-tcc icons

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

install: build          ## put it in /Applications and run it from there
	-pkill -x $(APP)
	rm -rf /Applications/$(APP).app
	cp -R $(APP_PATH) /Applications/$(APP).app
	/System/Library/Frameworks/CoreServices.framework/Versions/Current/Frameworks/LaunchServices.framework/Versions/Current/Support/lsregister -f /Applications/$(APP).app
	killall Dock
	open /Applications/$(APP).app

icons:                  ## regenerate the icon set from Design/app-icon.png (the master artwork)
	sips -Z 16   Design/app-icon.png --out $(ICONSET)/icon_16.png
	sips -Z 32   Design/app-icon.png --out $(ICONSET)/icon_16@2x.png
	sips -Z 32   Design/app-icon.png --out $(ICONSET)/icon_32.png
	sips -Z 64   Design/app-icon.png --out $(ICONSET)/icon_32@2x.png
	sips -Z 128  Design/app-icon.png --out $(ICONSET)/icon_128.png
	sips -Z 256  Design/app-icon.png --out $(ICONSET)/icon_128@2x.png
	sips -Z 256  Design/app-icon.png --out $(ICONSET)/icon_256.png
	sips -Z 512  Design/app-icon.png --out $(ICONSET)/icon_256@2x.png
	sips -Z 512  Design/app-icon.png --out $(ICONSET)/icon_512.png
	sips -Z 1024 Design/app-icon.png --out $(ICONSET)/icon_512@2x.png

stop:
	-pkill -x $(APP)

clean:
	rm -rf $(DERIVED) $(APP).xcodeproj

reset-tcc:            ## recovery only; grants normally survive rebuilds
	-tccutil reset Accessibility com.suraj.$(APP)
