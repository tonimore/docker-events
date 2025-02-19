# Сервис/контейнер для запуска пользовательских скриптов при стиарте Docker контейнеров

## Предистория

Иногда необхоимо в запущенный контейнер добавить сетевые маршруты. Например там, где более одного сетевого интефейса. И особенно это касается rootless контейнеров, которые не используют кастомные init системы, типа s6-overlay.

Также, при сложной конфигурации, бывает необходимо переназначить IP адреса для интерфесов типа macvlan или ipvlan l2. Или добавить policy routing, например чтобы пакеты пришедшие на eth1 возвращались не через eth0: default gateway, а тоже через eth1.  

Добавить маршруы невозможно как на этапе сборки контейнера так и в момент его запуска, изнутри.

Получается, что единственный способ это добавить маршруты после запуска контейнера, снаружи.

Обычно для этого используются команды:
```docker exec -u 0 <container> <command>```
или
```nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) <command>```

Для отслеживания событий запуска контейнеров используют события из ```docker events```

Для удобства был написан простой сервис который делает эту работу

## Принцип работы

Сервис использует ```docker events``` для отлова событи запуска контенера. После этого он делает несколько вещей:

1: смотрит Labels у запущенного контейнера. Если там есть label "docker-events.address", берется ее значение, разбивается по символу ";" и передается на выполнение команде:
```nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) ip address <value>```

2: смотрит Labels у запущенного контейнера. Если там есть label "docker-events.route", берется ее значение, разбивается по символу ";" и передается на выполнение команде:
```nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) ip route <value>```

2a: смотрит Labels у запущенного контейнера. Если там есть label "docker-events.host-route", берется ее значение, разбивается по символу ";" и передается на выполнение команде:
```ip route <value>```, те маршруты добавляются на хосте

3: смотрит Labels у запущенного контейнера. Если там есть label "docker-events.rule", берется ее значение, разбивается по символу ";" и передается на выполнение команде:
```nsenter -n -t $(docker inspect --format {{.State.Pid}} <container>) ip rule <value>```

Эти способы удобны тем, что необходимые маршруты и адреса можно хранить вместе с контейнером, например в docker-compose.yaml (см пример файла)
В настоящий момент, через labels: docker-events.xxxxx поддерживаются следующие команды:
- ip address ...
- ip route ...
- ip rule ...

но достаточно легко добавить любые другие.

4: ищет пользовательский скрипт с именем start.<container> и выполняет его

Этот способ удобен тем, что можно выполнять абсолютно ЛЮБЫЕ команды при старте конейнера, не только ip route

## Установка как сервис systemd 

Сервис предназначен для работы под управленим systemd. Устанавливается командой:

`$ docker_events.sh --instal`

## Запуск, как отдельный docker container

Достаточно собрать образ и запустить контейнер:
```
docker build . --tag=dehandler
docker run --rm --name=deh  --stop-signal=SIGKILL --restart=always -v /var/run/docker.sock:/var/run/docker.sock -v /proc:/proc --privileged  dehandler
```
См Dockerfile для подробностей.

## Запуск, в docker comopse

Примечание: Если у вас несколько docker compose приложений запущено на одном хосте, то достаточно одного экземпляра сервиса dehandler. В этом случаем его можно запустить, как отдельный контейнер.

Собрать образ: `docker build . --tag=dehandler` и добавить его запуск в docker-compose.yml:

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

## Настройка

Все переменные задаются в начале docker_events.sh, но обычно они не требуют изменения.

## Пример задания IP адресов и маршрутов в docker-compose 

см [Пример использования](./README.md#Usage-example)
