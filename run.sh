#!/bin/bash

#start cron
service cron start

#start
cd /workspace/apiservice
echo "start service"
python3 doorapiserver-patch.py
