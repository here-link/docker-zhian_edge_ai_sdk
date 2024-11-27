FROM faceedge01/zhian_edge_ai_sdk:bp3V203
MAINTAINER here.link

# Add the script to the Docker Image
COPY run.sh /workspace/run.sh
# Replace api server
COPY doorapiserver.py /workspace/apiservice/doorapiserver-patch.py

# Add the cron job
RUN crontab -l | { cat; echo "1 0 * * * /bin/bash /workspace/apiservice/auto-del-3-days-ago-image.sh"; } | crontab -
