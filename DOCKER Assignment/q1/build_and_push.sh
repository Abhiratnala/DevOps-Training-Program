#!/bin/bash
set -e

DOCKERHUB_USERNAME="yourusername"
IMAGE_NAME="webapp"
TAG="latest"

docker build -t $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG .

docker login

docker push $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG

echo "Image pushed: $DOCKERHUB_USERNAME/$IMAGE_NAME:$TAG"
