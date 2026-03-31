APP_NAME := FnVoiceInput
BUILD_DIR := .build/release
APP_DIR := $(BUILD_DIR)/$(APP_NAME).app
CONTENTS_DIR := $(APP_DIR)/Contents
MACOS_DIR := $(CONTENTS_DIR)/MacOS
RESOURCES_DIR := $(CONTENTS_DIR)/Resources
PLIST := Resources/Info.plist
ENTITLEMENTS := Resources/FnVoiceInput.entitlements
INSTALL_DIR := $(HOME)/Applications

.PHONY: build run install clean

build:
	swift build -c release
	mkdir -p "$(MACOS_DIR)" "$(RESOURCES_DIR)"
	cp "$(BUILD_DIR)/$(APP_NAME)" "$(MACOS_DIR)/$(APP_NAME)"
	cp "$(PLIST)" "$(CONTENTS_DIR)/Info.plist"
	cp "$(ENTITLEMENTS)" "$(RESOURCES_DIR)/FnVoiceInput.entitlements"
	codesign --force --deep --sign - --entitlements "$(ENTITLEMENTS)" "$(APP_DIR)"

run: build
	open "$(APP_DIR)"

install: build
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(APP_DIR)" "$(INSTALL_DIR)/$(APP_NAME).app"
	codesign --force --deep --sign - --entitlements "$(ENTITLEMENTS)" "$(INSTALL_DIR)/$(APP_NAME).app"

clean:
	rm -rf .build
