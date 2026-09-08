#!/bin/bash
# Clone Flutter SDK (stable channel)
git clone https://github.com/flutter/flutter.git -b stable --depth 1
export PATH="$PATH:`pwd`/flutter/bin"

# Check Flutter version & enable web
flutter doctor
flutter config --enable-web

# Install packages and build web bundle
flutter pub get
flutter build web --release