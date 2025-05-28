#!/bin/bash

# Start Nginx in the background
nginx -g "daemon off;" &

# Start the langflow application
langflow run
