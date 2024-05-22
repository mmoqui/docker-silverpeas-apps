FROM debian:bookworm

MAINTAINER Miguel Moquillon "miguel.moquillon@silverpeas.org"
LABEL name="Kerberos 5 service" description="Service to run Kerberos 5 within a Docker container" require="An LDAP service as backend"

ENV DEBIAN_FRONTEND=noninteractive

ENV KRB_REALM EXAMPLE.ORG
ENV KRB_DOMAIN ""
ENV KRB_ADMIN_USERNAME admin
ENV KRB_ADMIN_PASSWORD admin
ENV KRB_MASTER_KEY masterkey

ENV LDAP_BASE_DN dc=example,dc=org
ENV LDAP_ADMIN_USERNAME admin
ENV LDAP_ADMIN_PASSWORD admin
ENV LDAP_URL ldap://ldap

RUN apt-get update \
  && apt-get install -y locales vim ca-certificates iputils-ping \
      krb5-kdc krb5-kdc-ldap krb5-admin-server ldap-utils \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* /var/lib/log/* \
  && mkdir -p /usr/share/ca-certificates/home \
  && mkdir -p /etc/krb5/custom

COPY ./docker-entrypoint.sh /usr/local/bin/
COPY ./rootCA.crt /usr/share/ca-certificates/home/
COPY ./rootCA.pem /usr/share/ca-certificates/home/

RUN echo "home/rootCA.crt" >> /etc/ca-certificates.conf \
  && update-ca-certificates \
  && chmod +x /usr/local/bin/docker-entrypoint.sh

VOLUME ["/etc/krb5/custom"]

EXPOSE 88 464 749

ENTRYPOINT ["docker-entrypoint.sh"]