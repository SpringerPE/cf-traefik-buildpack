#!/usr/bin/env bash
[ -z "$DEBUG" ] || set -x
set -euo pipefail
shopt -s nullglob

ROOT="/home/vcap"
export APP_ROOT="${ROOT}/app"

CONFIGDIR_STATIC="${CONFIGDIR_STATIC:-${APP_ROOT}/traefik}"
CONFIGFILE="${CONFIGFILE:-${APP_ROOT}/traefik.yml}"

# Domain is only for admin endpoint and dashboard. If domain is not
# defined it takes the first assigned domain to the app, so, by default
# the admin interface will only be available there
DOMAIN=$(jq -r '.uris[0]' <<<"${VCAP_APPLICATION}")
PORT_HTTP="${PORT:-8080}"
# To disable the API, undefine the port or change it to 0
PORT_API="${PORT_API:-$PORT_HTTP}"

# Admin dashboard runs on PORT_API
ADMIN_HOST="${ADMIN_HOST:-$DOMAIN}"
ADMIN_AUTH_USER="${ADMIN_AUTH_USER:-admin}"
ADMIN_AUTH_PASSWORD="${ADMIN_AUTH_PASSWORD:-}"
ADMIN_PROMETHEUS="${ADMIN_PROMETHEUS:-1}"

###
ADMIN_ENTRYPOINT="http"
ADMIN_ENABLED=1
if [ -z "${PORT_API}" ]
then
    ADMIN_ENABLED=0
    PORT_API=0
elif [ "${PORT_API}" == "0" ]
then
    ADMIN_ENABLED=0
fi
ADMIN_CONFIGFILE="${CONFIGDIR_STATIC}/traefik-api.yml"

mkdir -p "${CONFIGDIR_STATIC}"
[ -r "${CONFIGDIR_STATIC}/traefik.yml" ] && CONFIGFILE="${CONFIGDIR_STATIC}/traefik.yml"
[ -r "${CONFIGDIR_STATIC}/traefik.yaml" ] && CONFIGFILE="${CONFIGDIR_STATIC}/traefik.yaml"
[ -r "${CONFIGDIR_STATIC}/traefik.toml" ] && CONFIGFILE="${CONFIGDIR_STATIC}/traefik.toml"
[ -r "${CONFIGFILE}" ] || touch "${CONFIGFILE}"

if [ "${ADMIN_ENABLED}" == "1" ] && [ ! -r "${ADMIN_CONFIGFILE}" ]
then
	cat <<- EOF >> "${CONFIGFILE}"
	api:
	  insecure: false
	  dashboard: true
	EOF
    [ "${PORT_API}" != "${PORT_HTTP}" ] && ADMIN_ENTRYPOINT="admin"
    if [ -z "${ADMIN_AUTH_PASSWORD}" ]
    then
        # Generate a random pass, lenght = 10
        ADMIN_AUTH_PASSWORD=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 10 | head -n 1 || true)
        echo "* Generated ${ADMIN_AUTH_USER} password in ${APP_ROOT}/${ADMIN_AUTH_USER}.password"
        echo "${ADMIN_AUTH_PASSWORD}" > "${APP_ROOT}/${ADMIN_AUTH_USER}.password"
    fi
    [ "${DOMAIN}" == "localhost" ] && ADMIN_HOST="localhost"
    cat <<- EOF > "${ADMIN_CONFIGFILE}"
	# API Configuration
	http:
	  middlewares:
	    auth:
	      realm: "${ADMIN_HOST}"
	      basicAuth:
	        users:
	        - "${ADMIN_AUTH_USER}:$(openssl passwd -crypt ${ADMIN_AUTH_PASSWORD})"
	  routers:
	    api:
	      entryPoints:
	      - ${ADMIN_ENTRYPOINT}
	      rule: "(Host(\`${ADMIN_HOST}\`) || Host(\`127.0.0.1\`)) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))"
	      service: 'api@internal'
	      middlewares:
	      - auth
	EOF
fi

# if configfile is empty, generate one based on the environment variables
if [ ! -s "${CONFIGFILE}" ]
then
	echo "* Using env variables to generate configuration ..."
    if [ "${ADMIN_ENABLED}" == "1" ] && [ "x${ADMIN_PROMETHEUS}" == "x1" ]
    then
        cat <<- EOF >> "${ADMIN_CONFIGFILE}"
		    metrics:
		      entryPoints:
		      - ${ADMIN_ENTRYPOINT}
		      rule: "(Host(\`${ADMIN_HOST}\`) || Host(\`127.0.0.1\`)) && PathPrefix(\`/metrics\`)"
		      service: 'api@internal'
		EOF
        cat <<- EOF > "${CONFIGFILE}"
		metrics:
		  prometheus:
		    addEntryPointsLabels: true
		    addServicesLabels: true
		    entryPoint: "${ADMIN_ENTRYPOINT}"
		EOF
    fi
	cat <<- EOF >> "${CONFIGFILE}"
	global:
	  checkNewVersion: false
	  sendAnonymousUsage: false
	log:
	  format: common
	  level: INFO
	accessLog:
	  bufferingSize: 10
	ping:
	  entryPoint: "ping"
	providers:
	  file:
	    directory: "${CONFIGDIR_STATIC}"
	    watch: false
	entryPoints:
	  ping:
	    address: "127.0.0.1:8181"
	  admin:
	    address: ":${PORT_API}"
	  http:
	    address: ":${PORT_HTTP}"
	    proxyProtocol:
	      insecure: true
	    forwardedHeaders:
	      insecure: true
	EOF
fi

echo ---
echo "${ADMIN_CONFIGFILE}"
echo ---
cat "${CONFIGFILE}"
echo ---

# run
traefik --configFile="${CONFIGFILE}" "$@"

