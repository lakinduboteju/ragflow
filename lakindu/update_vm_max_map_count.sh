#!/bin/bash
# Reference: https://ragflow.io/docs/dev/#start-up-the-server

echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.conf
