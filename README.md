# Systemd service for run user actions on docker container starts 
[Русская версия](README_RU.md)

## Common Info

Sometimes it is needed to add routes to the container. It is often neccessary for containers that have two or more network interfaces, especialiy if they are rootless and don't use custom init system like [s6-overlay](https://github.com/just-containers/s6-overlay) or something like that.

In this case it is impossible to add routes either during container create or after it was started (inside container).
So the only way to add routes to the running container is to run some script on the host after the container has started.

It can usually be done with following command:
```
docker exec -u 0 <container> <command>
```
or
```
nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) <command>
```
To track container start events ```docker events``` command is commonly used
So here is a simple service that will do that.

## How it works

The service uses ```docker events``` to catch container start events. Then it does a couple of things:

1: It checks container's labels for "docker-events.route" label, takes its value, splits it into parts with semicolon and passes every part to the command:  
```nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) ip route <value>```

This method is useful because we can keep routes together with the container, right in the docker-compose.yaml. See example bellow.

2: It dinds user-defined script named "start.<container>" and executes it

This method is convenient because you can execute **any** commands when the container starts, not only add routes.

## Installation

The service acts as systemd service and can be installed with:
```
$ docker_events.sh --install
```

## Configuration

All the necessary variables are set at the beginning of the script, but they don't usually need to be changed.

## Example of docker-compose.yaml

``` yaml
version: "3.8"
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
      docker-events.route: "delete default;add default via 33.156.88.1;add 10.0.0.0/8 via 172.20.20.1;add 192.168.0.0/16 via 172.20.20.1" 

```
In our example, after the start of the container, the following commands will be executed:
```
nsenter ... ip route delete default
nsenter ... ip route add default via 33.156.88.1
nsenter ... ip route add 10.0.0.0/8 via 172.20.20.1
nsenter ... ip route add 192.168.0.0/16 via 172.20.20.1
```

