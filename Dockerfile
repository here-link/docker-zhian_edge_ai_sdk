FROM faceedge01/zhian_edge_ai_sdk:bp3V104
MAINTAINER here.link

# Add the script to the Docker Image
ADD run.sh /workspace/run.sh

# Add the cron job
RUN crontab -l | { cat; echo "1 0 * * * /bin/bash /workspace/apiservice/auto-del-3-days-ago-image.sh"; } | crontab -

RUN chmod 0644 /workspace/run.sh
