# Systemd service for run user actions on docker container starts 
[Русская версия](README_RU.md)

## Common Info

Sometimes it need to add routes to the container. It often neccessary for containers that have two or more network interfaces. Especiality if it is rootless and doesn't use custom init system like [s6-overlay](https://github.com/just-containers/s6-overlay) and so on.

In this case it impossible to add routes neither during container create nor after it was started (inside container)  

So the only way to add routes to the running container is to run some script on the host after container started.

It usually can be done with next command:
```
docker exec -u 0 <container> <command>
```
or
```
nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) <command>
```

To track container start events common used ```docker events```

So here is simple service that will do that.

## How it works

Service use ```docker events``` to catch container start events. Then it do a couple of things:

1: Checks container's Labels for "docker-events.route" label. Takes it value, split to parts by semicolon and pass every part to the command:  
```nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) ip route <value>```

This method is useful because we can keep routes together with the container. Actially in the docker-compose.yaml See example bellow.

2: Finds user defined ищет пользовательский скрипт с именем start.<container> и выполняет его

This method is convenient because you can execute **any** commands when the container starts, not only add routes

## Installation

The service acts as systemd service and can be installed with:
```
$ docker_events.sh --install
```

## Configuration

All the necessary variables set in the begining of the script, but usually they don't need to be changed.

## Example of docker-compose.yaml

```
version: "3.8"
networks:
  wan:
    # In this example we create IPVLAN L2 network
    driver: ipvlan
    driver_opts:
      parent: eth1
    ipam:
      config:
      - subnet: 33.156.88.0/24
        gateway: 33.156.88.1
        ip_range: 33.156.88.128/25
  lan: 
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
In our example, after starting the container, the following commands will be executed:
```
nsenter ... ip route delete default
nsenter ... ip route add default via 33.156.88.1
nsenter ... ip route add 10.0.0.0/8 via 172.20.20.1
nsenter ... ip route add 192.168.0.0/16 via 172.20.20.1
```

