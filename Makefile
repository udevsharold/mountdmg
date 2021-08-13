export ARCHS = arm64 arm64e

export DEBUG = 0
export FINALPACKAGE = 1

export PREFIX = $(THEOS)/toolchain/Xcode11.xctoolchain/usr/bin/

TARGET := iphone:clang:latest:7.0

include $(THEOS)/makefiles/common.mk

TOOL_NAME = mountdmg

mountdmg_FILES = main.mm
mountdmg_CFLAGS = -fobjc-arc
mountdmg_CODESIGN_FLAGS = -Sentitlements.plist
mountdmg_INSTALL_PATH = /usr/local/bin

include $(THEOS_MAKE_PATH)/tool.mk
