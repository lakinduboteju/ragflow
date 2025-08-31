#!/bin/bash
cd ./docker
git checkout -f v0.20.4

# Use CPU for embedding and DeepDoc tasks:
docker compose -f docker-compose-https.yml up -d
