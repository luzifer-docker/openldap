#!/bin/bash
set -euxo pipefail

export SLAPD_CONFDIR=/etc/openldap/slapd.d
export SLAPD_DATADIR=/var/lib/openldap/openldap-data

# Hash passwords
[ -n "${SLAPD_PASSWORD:-}" ] && export SLAPD_PASSWORD=$(slappasswd -h '{SSHA}' -s "${SLAPD_PASSWORD}" -n)
[ -n "${SLAPD_CONFIG_PASSWORD:-}" ] && export SLAPD_CONFIG_PASSWORD=$(slappasswd -h '{SSHA}' -s "${SLAPD_CONFIG_PASSWORD}" -n)

# Generate SLAPD_SUFFIX from given domain
IFS="."
declare -a dc_parts=(${SLAPD_DOMAIN:-example.com})
unset IFS

for dc_part in "${dc_parts[@]}"; do
  dc_string="${dc_string:-},dc=${dc_part}"
done

export SLAPD_SUFFIX=${dc_string#,}

# Add included module configs to base directory
cp -r /config/modules /etc/openldap/

# Configure and start slapd
if [ "${1:-}" = 'slapd' ]; then
  # When not limiting the open file descritors limit, the memory consumption of
  # slapd is absurdly high. See https://github.com/docker/docker/issues/8231
  ulimit -n 8192

  # Fix missing directory
  mkdir -p /run/openldap && chown ldap:ldap /run/openldap

  # Generate templates
  korvike -i /config/slapd.conf -o /etc/openldap/slapd.conf
  korvike -i /config/slapd.ldif -o /etc/openldap/slapd.ldif
  korvike -i /config/init.ldif -o /tmp/init.ldif

  if ! [ -d "${SLAPD_CONFDIR}/cn=config" ]; then
    # Generate basic configuration
    mkdir -p ${SLAPD_CONFDIR}
    slapadd -n 0 -F ${SLAPD_CONFDIR} -l /etc/openldap/slapd.ldif
    slapadd -F ${SLAPD_CONFDIR} -b ${SLAPD_SUFFIX} -l /tmp/init.ldif

    # Load schemas into configuration database
    if [ -n "$SLAPD_ADDITIONAL_SCHEMAS" ]; then
      IFS=","
      declare -a schemas=($SLAPD_ADDITIONAL_SCHEMAS)
      unset IFS

      for schema in "${schemas[@]}"; do
        slapadd -n 0 -F ${SLAPD_CONFDIR} -l "/etc/openldap/schema/${schema}.ldif"
      done
    fi

    # Activate module configurations
    if [ -n "$SLAPD_ADDITIONAL_MODULES" ]; then
      IFS=","
      declare -a modules=($SLAPD_ADDITIONAL_MODULES)
      unset IFS

      for module in "${modules[@]}"; do
        module_file="/etc/openldap/modules/${module}.ldif"

        if [ "$module" == 'ppolicy' ]; then
          SLAPD_PPOLICY_DN_PREFIX="${SLAPD_PPOLICY_DN_PREFIX:-cn=default,ou=policies}"

          sed -i "s/\(olcPPolicyDefault: \)PPOLICY_DN/\1${SLAPD_PPOLICY_DN_PREFIX}$dc_string/g" $module_file
        fi

        slapadd -n0 -F ${SLAPD_CONFDIR} -l "$module_file"
      done
    fi

    chown -R ldap:ldap ${SLAPD_CONFDIR} ${SLAPD_DATADIR}
  else
    # Check for configuration variables when container is already configured
    if (env | grep -q "SLAPD_"); then
      echo "Info: LDAP container is already configured, SLAPD_* env variables are ignored."
    fi
  fi

  exec "$@"
fi

# Other binary was called, execute directly
exec "$@"
