#!/bin/bash

# Create soft-signed SSL certificate

# Self-signed certificates are suitable for internal testing or development environments,
# but they are not trusted by default by web browsers or clients in production environments.
# For production use, a certificate signed by a trusted Certificate Authority (CA) is recommended.

openssl genrsa -des3 -out server.key 2048
openssl req -new -key server.key -out server.csr
openssl x509 -req -days 365 -in server.csr -signkey server.key -out server.crt
