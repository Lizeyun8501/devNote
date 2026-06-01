#!/bin/bash
set -e
unset MISE_DATA_DIR MISE_CONFIG_FILE_ROOT MISE_USE_TOML MISE_SHELL 2>/dev/null || true
export ANDROID_HOME=/opt/android-sdk
export JAVA_HOME=/root/.local/share/mise/installs/java/11.0.2
export PATH="/root/.local/share/mise/installs/java/11.0.2/bin:/root/.local/share/mise/installs/gradle/8.14.4/gradle-8.14.4/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/flutter/bin"
cd /workspace/devnote/android
java -version 2>&1
gradle assembleDebug --no-daemon 2>&1
