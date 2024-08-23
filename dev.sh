#!/usr/bin/env bash

git submodule init 
git submodule update --remote --merge
docker compose up -d
docker exec -it flutter flutter run