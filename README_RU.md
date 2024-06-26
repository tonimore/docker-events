# Сервис для отлова событий Docker и запуска скриптоd

## Предистория

Иногда необхоимо в запущенный контейнер добавить сетевые маршруты. Например там, где более одного сетевого интефейса. И особенно это касается rootless контейнеров, которые не используют кастомные init системы, типа s6-overlay.

Также, при сложной конфигурации, бывает необходимо переназначить IP адреса для интерфесов типа macvlan или ipvlan l2.

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

Эти способы удобны тем, что необходимые маршруты и адреса можно хранить вместе с контейнером, например в docker-compose.yaml (см пример файла)

3: ищет пользовательский скрипт с именем start.<container> и выполняет его

Этот способ удобен тем, что можно выполянять любые команды при старте конейнера, не только ip route

## Установка

Сервис предназначен для работы под управленим systemd. Устанавливается командой:

$ docker_events.sh --instal

## Настройка

Все переменные задаются в начале docker_events.sh, но обычно они не требую изменения.
