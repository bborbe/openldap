FROM alpine:3.14
MAINTAINER Benjamin Borbe <bborbe@rocketnews.de>

RUN apk add \
	--update \
	ca-certificates \
	openldap \
	openldap-clients \
	openldap-back-hdb \
	openldap-back-bdb \
	openldap-overlay-memberof \
	ldapvi \
	bash \
	&& rm -rf /var/cache/apk/*

COPY files/slapd.conf /slapd.conf.template
COPY files/DB_CONFIG /DB_CONFIG

ENV LDAP_SECRET 'S3CR3T'
ENV LDAP_SUFFIX 'dc=example,dc=com'
ENV LDAP_ROOTDN 'cn=admin,dc=example,dc=com'

EXPOSE 389 636

COPY files/entrypoint.sh /usr/local/bin/
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

#CMD ["slapd", "-d", "256", "-u", "ldap", "-g", "ldap"]
#CMD ["slapd", "-d", "16383", "-u", "ldap", "-g", "ldap"]
CMD ["slapd", "-d", "32768", "-u", "ldap", "-g", "ldap"]
