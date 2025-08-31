#!/bin/bash
# Installing Docker and Docker Compose on EC2 instance running Amazon Linux 2023

# Stop at first error
set -e

# Installing Docker
# Reference: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-docker.html
sudo yum update -y
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user

# Installing Docker Compose
# Reference: https://docs.docker.com/compose/install/linux
DOCKER_CONFIG=${DOCKER_CONFIG:-$HOME/.docker}
mkdir -p $DOCKER_CONFIG/cli-plugins
curl -SL https://github.com/docker/compose/releases/download/v2.39.2/docker-compose-linux-x86_64 -o $DOCKER_CONFIG/cli-plugins/docker-compose
chmod +x $DOCKER_CONFIG/cli-plugins/docker-compose

sudo reboot
