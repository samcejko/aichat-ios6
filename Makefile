# AIChat - universal OpenRouter chat client for jailbroken iOS 6.x (armv7)
# Built with Theos. Deployment target iOS 6.0, compiled against the iOS 9.3 SDK.

TARGET := iphone:clang:9.3:6.0
ARCHS := armv7
DEBUG ?= 0

# Device used by `make install` (Theos) - overridden by tools/ipad.ps1 anyway
THEOS_DEVICE_IP ?= 192.168.137.17
THEOS_DEVICE_USER ?= root

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME := AIChat

AIChat_FILES := $(wildcard src/*.m) $(wildcard src/*/*.m) \
                vendor/mbedtls_glue.c \
                $(wildcard vendor/mbedtls/library/*.c)

AIChat_FRAMEWORKS := UIKit Foundation CoreGraphics QuartzCore Security MobileCoreServices ImageIO QuickLook

# Flags for every C-family file (also the vendored mbedTLS sources)
AIChat_CFLAGS := -Isrc -Isrc/Net -Isrc/Model -Isrc/Chat -Isrc/Markdown -Isrc/UI -Isrc/Theme -Isrc/Util \
                 -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library \
                 -Os -fvisibility=hidden \
                 -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                 -Wno-deprecated-declarations -Wno-unknown-warning-option

# Objective-C only: ARC and hard failure on any API newer than iOS 6.0
AIChat_OBJCFLAGS := -fobjc-arc -Wunguarded-availability -Werror=unguarded-availability

AIChat_LDFLAGS := -lz

include $(THEOS)/makefiles/application.mk
