FROM alpine as builder

ARG GIT_REF_ICINGA2=master
ARG GIT_REF_ICINGAWEB2=master

RUN apk add git

WORKDIR /dl
RUN git clone --depth 1 --branch ${GIT_REF_ICINGA2} https://github.com/Icinga/icinga2.git
RUN git clone --depth 1 --branch ${GIT_REF_ICINGAWEB2} https://github.com/Icinga/icingaweb2.git

FROM mysql:8.0.17

COPY --from=builder /dl/icinga2/lib/db_ido_mysql/schema/mysql.sql /app/icinga2-schema.sql
COPY --from=builder /dl/icingaweb2/etc/schema/mysql.schema.sql /app/icingaweb2-schema.sql
COPY ./mysql/* /app/

CMD [ "/app/start.sh" ]
