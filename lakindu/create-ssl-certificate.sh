#!/bin/bash

# Create soft-signed SSL certificate

# Self-signed certificates are suitable for internal testing or development environments,
# but they are not trusted by default by web browsers or clients in production environments.
# For production use, a certificate signed by a trusted Certificate Authority (CA) is recommended.

# Stop at first error
set -e

sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout ./server.key -out ./server.crt
