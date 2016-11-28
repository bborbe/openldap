#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail
set -o errtrace

ulimit -n 8192

if [ "$1" = 'slapd' ]; then
	ldap_secret=${LDAP_SECRET:-'S3CR3T'}
	ldap_suffix=${LDAP_SUFFIX:-'dc=my-domain,dc=com'}
	ldap_rootdn=${LDAP_ROOTDN:-'cn=Manager,dc=my-domain,dc=com'}

	ldap_secret=`slappasswd -s ${ldap_secret}`
	unset LDAP_SECRET

	sed_script=""
	for var in ldap_secret ldap_suffix ldap_rootdn; do
		sed_script+="s~{{$var}}~${!var}~g;"
	done

	echo "create slapd.conf"
	cat /etc/openldap/slapd.conf.template | sed -e "$sed_script" > /etc/openldap/slapd.conf

	echo "starting openldap $@"
fi

exec "$@"
