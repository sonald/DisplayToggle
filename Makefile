APP = DisplayToggle.app

all: $(APP)

DisplayToggle: main.swift
	swiftc -O -framework Cocoa main.swift -o $@

$(APP): DisplayToggle
	mkdir -p $(APP)/Contents/MacOS
	cp DisplayToggle $(APP)/Contents/MacOS/
	printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict>\n<key>CFBundleIdentifier</key><string>local.display-toggle</string>\n<key>CFBundleName</key><string>DisplayToggle</string>\n<key>CFBundleExecutable</key><string>DisplayToggle</string>\n<key>LSUIElement</key><true/>\n</dict></plist>\n' > $(APP)/Contents/Info.plist

run: $(APP)
	open $(APP)

clean:
	rm -rf DisplayToggle $(APP)

.PHONY: all run clean
