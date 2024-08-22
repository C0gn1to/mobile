#!/bin/bash

git config --global --add safe.directory /mobile

# Extract submodule paths from .gitmodules
submodule_paths=$(git submodule status | awk '{ print $2 }')

# Run the specified commands for each submodule
for submodule in $submodule_paths; do
  echo "Processing submodule $submodule"
  cd $submodule
  flutter pub get
  dart run build_runner clean
  dart run build_runner build --delete-conflicting-outputs
  flutter clean
  cd ..
done