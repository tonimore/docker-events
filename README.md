# Systemd service / Container for run user actions on docker container starts 
[Русская версия](README_RU.md)

## Common Info

Sometimes it is needed to add routes to the container. It is often neccessary for containers that have two or more network interfaces, especialiy if they are rootless and don't use custom init system like [s6-overlay](https://github.com/just-containers/s6-overlay) or something like that.

Also, with a complex configuration, it may be necessary to reconfigure IP addresses for interfaces such as "macvlan" or "ipvlan l2". Or add policy routing, for example, so that packets arriving on eth1 are returned not through eth0: default gateway, but also through eth1.

In this case it is impossible to add routes either during container create or after it was started (inside container).

So the only way to add routes to the running container or reconfigure IP addresses is to run some script on the host after the container has started.

It can usually be done with following command:
```
docker exec -u 0 <container> <command>
```
or
```
nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) <command>
```
To track container start events `docker events` command is commonly used
So here is a simple service that will do that.

## How it works

The service uses `docker events` to catch container start events. Then it does a couple of things:

1: It checks container's labels for "docker-events.address" label, takes its value, splits it into parts with semicolon and passes every part to the command:  
```nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) ip address <value>```
For example, label `docker-events.address: "add 10.0.1.4/16 dev eth0"` will run `ip address add 10.0.1.4/16 dev eth0` inside the container.  

2: It checks container's labels for "docker-events.route" label, takes its value, splits it into parts with semicolon and passes every part to the command:  
```nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) ip route <value>```
For example, label `delete default;add default via 33.156.88.1;add 10.0.0.0/8 via 172.20.20.1` will run inside the container:
```
ip route delete default 
ip route add default via 33.156.88.1
ip route add 10.0.0.0/8 via 172.20.20.1
```  

2a: It checks container's labels for "docker-events.host-route" label, takes its value, splits it into parts with semicolon and passes every part to the command:  
```ip route <value>```, so routes will be added on the host

For example, label `docker-events.host-route: "delete $VPN_IP/26;add $VPN_IP/16 via $INT_IF_IP"` will run inside the container (of course, it assumed that $VPN and $INT_IF_IP are set):

```
ip route delete $VPN
ip route add $VPN via $INT_IF_IP
```

3: It checks container's labels for "docker-events.rule" label, takes its value, splits it into parts with semicolon and passes every part to the command:  
```ip rule <value>```

Thouse methods are useful because we can keep routes configuration together with the container, right in the docker-compose.yaml. See example bellow.
Currently, the following commands are supported via labels: docker-events.xxxxx:
- ip address ...
- ip route ...
- ip rule ...

but it is easy to add any others.

4: It finds user-defined script named "start.<container>" and executes it

This method is convenient because you can execute **any** commands when the container starts, not only `add routes`.

## Installation as a systemd service on host

The service acts as systemd service and can be installed with:
```
$ docker_events.sh --install
```

## Run as standalone docker container

Just build the image and start container:
```
docker build . --tag=dehandler
docker run --rm --name=deh  --stop-signal=SIGKILL --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /proc:/proc --privileged  dehandler
```
See Dockerfile for details.

## Run as part of docker comopse

Note: If you are running multiple docker-compose apps on the same host, add the dehandler service to only one of them — that will be sufficient. In general, in such cases, it is better to run dehandler as a standalone container.

build image: `docker build . --tag=dehandler` and add it to your docker-compose.yml, like this:

```yaml
services:
  dehandler:
    image: dehandler
    container_name: deh
    restart: unless-stopped
    stop_signal: SIGKILL
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /proc:/proc
    privileged: true

  your_some_service:
    depends_on:  
      dehandler:
        required: true
        condition: service_started 
  ...   

```

## Configuration

All the necessary variables are set at the beginning of the script, but they don't usually need to be changed.

## Usage example

All magic is in labels section:

``` yaml
networks:
  wan:
    # In this example we create IPVLAN L2 network that connected to eth1 interface 
    driver: ipvlan
    driver_opts:
      parent: eth1
    ipam:
      config:
      - subnet: 33.156.88.0/24
        gateway: 33.156.88.1
        ip_range: 33.156.88.128/25
  lan:
    # just regular user-defined bridge
    driver: bridge
    ipam:
      config:
      - subnet: 172.20.20.0/24
services:
  dualnet:
    image: someimage:latest
    ports:
      - "4000:4000"
    networks: 
      wan:
      lan:
    labels: 
      # Add secondary IP addfress to the interface
      docker-events.address: "add 10.0.1.4/16 dev eth0"   
      # change default gateway and add routes
      docker-events.route: "delete default;add default via 33.156.88.1;add 10.0.0.0/8 via 172.20.20.1;add 192.168.0.0/16 via 172.20.20.1"
      # here we recreate host (not the container) routes based on enviroment variables: for example VPN_IP=10.0.8.0 INT_IF_IP=172.20.20.1
      # this is not availble if run as contaner! 
      docker-events.host-route: "delete $VPN_IP/26;add $VPN_IP/16 via $INT_IF_IP"

```
In our example, after the start of the container, the following commands will be executed:
```
nsenter ... ip address add 10.0.1.4/16 dev eth0
nsenter ... ip route delete default
nsenter ... ip route add default via 33.156.88.1
nsenter ... ip route add 10.0.0.0/8 via 172.20.20.1
nsenter ... ip route add 192.168.0.0/16 via 172.20.20.1
delete 10.0.8.0/16 
add 10.0.8.0/16  via 172.20.20.1
```

