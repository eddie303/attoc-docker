FROM ubuntu:latest
MAINTAINER Szasz Eduard Istvan <eduard.istvan.sas@gmail.com>

COPY attoc.pl /usr/local/bin/
COPY entrypoint.sh /usr/local/bin

RUN rm -f /etc/localtime && ln -s /usr/share/zoneinfo/Europe/Bucharest /etc/localtime \
 && echo "Europe/Bucharest" > /etc/timezone \
 && apt-get update \
 && apt-get -y dist-upgrade \
 && apt-get install -y libmp3-info-perl libmp3-tag-perl libaudio-wav-perl libcompress-raw-zlib-perl \
 && chmod +x /usr/local/bin/*

CMD ["/usr/local/bin/entrypoint.sh"]
