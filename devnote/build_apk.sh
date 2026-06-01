#!/bin/bash
set -e
export ANDROID_HOME=/opt/android-sdk
export JAVA_HOME=/root/.local/share/mise/installs/java/11.0.2
export PATH="$JAVA_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/opt/flutter/bin"
cd /workspace/devnote
echo "Using Java: $(java -version 2>&1 | head -1)"
echo "Using Flutter: $(flutter --version | head -1)"
flutter config --android-sdk /opt/android-sdk
flutter build apk --debug 2>&1
