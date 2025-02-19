# build: docker build . --tag=dehandler
# run: docker run --rm --name=deh  --stop-signal=SIGKILL --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /proc:/proc --privileged  dehandler

FROM docker:27.5.0-cli-alpine3.21
RUN mkdir -p /app/scripts
ENV scripts_dir=/app/scripts 
ENV in_docker=1
ADD --chmod=755 docker_events.sh /app/docker_events.sh
ENTRYPOINT [ "/bin/sh", "-c", "/app/docker_events.sh --service" ]
