FROM alpine:3.4
MAINTAINER Benjamin Borbe <bborbe@rocketnews.de>

RUN apk add --update openldap openldap-clients openldap-back-hdb openldap-back-bdb ldapvi bash && rm -rf /var/cache/apk/*

ADD slapd.conf /etc/openldap/slapd.conf.template
ADD DB_CONFIG /var/lib/openldap/openldap-data/DB_CONFIG

EXPOSE 389 636

COPY entrypoint.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

#CMD ["slapd", "-d", "256", "-u", "ldap", "-g", "ldap"]
#CMD ["slapd", "-d", "16383", "-u", "ldap", "-g", "ldap"]
CMD ["slapd", "-d", "32768", "-u", "ldap", "-g", "ldap"]
