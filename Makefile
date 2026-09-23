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

# Flags for every C-family file (also the vendored mbedTLS sources)
AIChat_CFLAGS := -Isrc -Isrc/Net -Isrc/Model -Isrc/Chat -Isrc/Markdown -Isrc/UI -Isrc/Theme -Isrc/Util \
                 -Ivendor -Ivendor/mbedtls/include -Ivendor/mbedtls/library \
                 -Ivendor/iosMath/iosMath/lib -Ivendor/iosMath/iosMath/render -Ivendor/iosMath/iosMath/render/internal \
                 -Os -fvisibility=hidden \
                 -Wall -Wno-unused-variable -Wno-unused-function -Wno-unused-but-set-variable \
                 -Wno-deprecated-declarations -Wno-unknown-warning-option \
                 -Wno-nullability-completeness -Wno-nullability-completeness-on-arrays -Wno-error

# Objective-C only: ARC; APIs newer than iOS 6.0 are warnings here and turned into errors for our own
# sources by the pragma in src/ORCommon.h (vendored code only warns).
AIChat_OBJCFLAGS := -fobjc-arc -Wunguarded-availability

AIChat_LDFLAGS := -lz

include $(THEOS)/makefiles/application.mk
