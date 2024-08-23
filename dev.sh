#!/usr/bin/env bash

git submodule init 
git submodule update --remote --merge
docker compose up -d
docker wait flutter  # Waiting for it to finish building
docker start flutter
docker exec -it flutter /bin/bash -c "adb connect emulator:5555 && flutter run"