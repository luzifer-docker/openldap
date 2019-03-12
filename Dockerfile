FROM alpine:3.9

RUN set -ex \
 && apk --no-cache add \
      bash \
      curl \
      openldap \
      openldap-back-mdb \
      openldap-clients \
      openldap-overlay-memberof \
      openldap-overlay-ppolicy \
      openldap-overlay-refint \
 && curl -sSfLo /usr/local/bin/korvike "https://github.com/Luzifer/korvike/releases/download/v0.4.1/korvike_linux_amd64" \
 && chmod 0755 /usr/local/bin/korvike \
 && apk --no-cache del curl \
 && rm -rf /var/cache/apk/*

COPY docker-entrypoint.sh /
COPY config /config

EXPOSE 389

VOLUME ["/etc/openldap/slapd.d", "/var/lib/openldap/openldap-data"]

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["slapd", "-d", "32768", "-u", "ldap", "-g", "ldap"]
