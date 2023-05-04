#!/usr/bin/env bash

echo "data:image/svg+xml;base64,$(cat $1 | base64 | tr -d '\r\n')"
