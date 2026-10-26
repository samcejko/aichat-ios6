# AIChat - universal OpenRouter chat client for jailbroken iOS. One source tree, two packages (Theos):
#   make package                               armv7 for iOS 6.x (the iOS 9.3 SDK, deployment target 6.0)
#   make package THEOS_PACKAGE_SCHEME=rootless arm64 for iOS 14-17 (the iOS 16.5 SDK, deployment target 14.0):
#                                              the .deb for rootless jailbreaks, the IPA for TrollStore
# (`make clean` between the two; CI builds both, see .github/workflows/build.yml)

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
TARGET := iphone:clang:16.5:14.0
ARCHS := arm64
else
TARGET := iphone:clang:9.3:5.0
ARCHS := armv7
endif
DEBUG ?= 0

# Device used by `make install` (Theos) - overridden by tools/ipad.ps1 anyway
THEOS_DEVICE_IP ?= 192.168.137.17
THEOS_DEVICE_USER ?= root

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := AIChat

# iosMath (LaTeX rendering, MIT) is fetched into vendor/iosMath by CI; the NS*/AppKit files are macOS only.
IOSMATH_FILES := $(filter-out %NSBezierPath+addLineToPoint.m %NSColor+HexString.m %NSView+backgroundColor.m, \
                   $(wildcard vendor/iosMath/iosMath/lib/*.m) \
                   $(wildcard vendor/iosMath/iosMath/render/*.m) \
                   $(wildcard vendor/iosMath/iosMath/render/internal/*.m))

AIChat_FILES := $(wildcard src/*.m) $(wildcard src/*/*.m) \
                vendor/mbedtls_glue.c \
                $(wildcard vendor/mbedtls/library/*.c) \
                $(IOSMATH_FILES)

AIChat_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore CoreText Security ImageIO QuickLook AssetsLibrary
ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
# the system photo picker of iOS 14 and newer (src/UI/ORChatViewController.m)
AIChat_FRAMEWORKS += PhotosUI
endif

# Flags for every C-family file (also the vendored mbedTLS sources)
AIChat_CFLAGS := -Isrc -Isrc/Net -Isrc/Model -Isrc/Chat -Isrc/Markdown -Isrc/UI -Isrc/Theme -Isrc/Util \
                 -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library \
                 -Ivendor/iosMath/iosMath/lib -Ivendor/iosMath/iosMath/render -Ivendor/iosMath/iosMath/render/internal \
                 -Os -fvisibility=hidden \
                 -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                 -Wno-deprecated-declarations -Wno-unknown-warning-option \
                 -Wno-nullability-completeness -Wno-nullability-completeness-on-arrays -Wno-error

# Objective-C only: ARC; APIs newer than the deployment target are warnings here and turned into errors for our
# own sources by the pragma in src/ORCommon.h (vendored code only warns). src/Util/ORModern.m bridges the newer
# iOS on its own terms and opts out. UIKit comes first everywhere because iosMath's UIColor+HexString.m tests
# TARGET_OS_IPHONE without including anything (the iOS 16.5 SDK treats that as an error) and needs UIColor.
AIChat_OBJCFLAGS := -fobjc-arc -Wunguarded-availability -include UIKit/UIKit.h

AIChat_LDFLAGS := -lz

include $(THEOS)/makefiles/application.mk

AICHAT_STAGED_APP := $(THEOS_STAGING_DIR)/Applications/AIChat.app

ifeq ($(THEOS_PACKAGE_SCHEME),rootless)
# The arm64 bundle: iOS 14.0+, arm64 required, a launch screen the system draws instead of the iOS 6 launch
# images (tools/modern_bundle.py), signed again with the arm64 entitlements afterwards.
after-stage::
	python3 "$(THEOS_PROJECT_DIR)/tools/modern_bundle.py" "$(AICHAT_STAGED_APP)"
	ldid -S"$(THEOS_PROJECT_DIR)/entitlements-arm64.xml" "$(AICHAT_STAGED_APP)/AIChat"
# The .deb is for rootless jailbreaks (iOS 15 and newer; Theos sets Architecture: iphoneos-arm64 and the /var/jb
# prefix itself) and tells the home screen about the app when installed or removed.
before-package::
	sed -i -e 's/^Depends: .*/Depends: firmware (>= 15.0)/' "$(THEOS_STAGING_DIR)/DEBIAN/control"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = configure ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && { uicache -p /var/jb/Applications/AIChat.app >/dev/null 2>&1 || uicache -a >/dev/null 2>&1; }' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postinst"
	printf '%s\n' '#!/bin/sh' '[ "$$1" = remove ] || exit 0' \
		'command -v uicache >/dev/null 2>&1 && uicache -a >/dev/null 2>&1' \
		'exit 0' > "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
	chmod 0755 "$(THEOS_STAGING_DIR)/DEBIAN/postinst" "$(THEOS_STAGING_DIR)/DEBIAN/postrm"
endif
