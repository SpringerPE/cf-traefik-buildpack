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
PORT_API="${PORT_API:-$PORT}"

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
	        - "${ADMIN_AUTH_USER}:$(openssl passwd -crypt ${ADMIN_AUTH_PASSWORD)"
	  routers:
	    api:
	      entryPoints:
	      - ${ADMIN_ENTRYPOINT}
	      rule: "(Host(\`${ADMIN_HOST}\`) || Host(\`127.0.0.1\`)) && (PathPrefix(\`/api\`) || PathPrefix(\`/dashboard\`))"
	      service: 'api@internal'
	      middlewares:
	      - auth
	EOF
    if [ "x${ADMIN_PROMETHEUS}" == "x1" ]
    then
        cat <<- EOF >> "${ADMIN_CONFIGFILE}"
		    metrics:
		      entryPoints:
		      - ${ADMIN_ENTRYPOINT}
		      rule: "(Host(\`${ADMIN_HOST}\`) || Host(\`127.0.0.1\`)) && PathPrefix(\`/metrics\`)"
		      service: 'api@internal'
		EOF
        cat <<- EOF >> "${CONFIGFILE}"
		metrics:
		  prometheus:
		    addEntryPointsLabels: true
		    addServicesLabels: true
		    entryPoint: "${ADMIN_ENTRYPOINT}"
		EOF
    fi
fi

# if configfile is empty, generate one based on the environment variables
if [ ! -s "${CONFIGFILE}" ]
then
	echo "* Using env variables to generate configuration ..."
	cat <<- EOF > "${CONFIGFILE}"
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

# run
traefik --configFile="${CONFIGFILE}" "$@"






























# See bin/finalize to check predefined vars
ROOT="/home/vcap"
export APP_ROOT="${ROOT}/app"
export AUTH_ROOT="${ROOT}/auth"
export APP_CONFIG="${ROOT}/.config/rclone/rclone.conf"
export APP_VCAP_SERVICES="${APP_ROOT}/VCAP_SERVICES"
















### Configuration env vars
# https://rclone.org/docs/#environment-variables

export RCLONE_RC_ADDR=":${PORT}"
export AUTO_START_ACTIONS="${AUTO_START_ACTIONS:-$APP_ROOT/post-start.sh}"
export BINDING_NAME="${BINDING_NAME:-}"
export GCS_LOCATION="${GCS_LOCATION:-europe-west4}"

export CLONE_SOURCE_SERVICE="${CLONE_SOURCE_SERVICE:-}"
export CLONE_SOURCE_BUCKET="${CLONE_SOURCE_BUCKET:-}"
export CLONE_DESTINATION_SERVICE="${CLONE_DESTINATION_SERVICE:-}"
export CLONE_DESTINATION_BUCKET="${CLONE_DESTINATION_BUCKET:-}"
export CLONE_TIMER="${CLONE_TIMER:-0}"
export CLONE_MODE="${CLONE_MODE:-copy}"

export AUTH_USER="${AUTH_USER:-admin}"
export AUTH_PASSWORD="${AUTH_PASSWORD:-}"

export RCLONE_RC_SERVE="${RCLONE_RC_SERVE:-true}"
export RCLONE_CONFIG="${RCLONE_CONFIG:-$APP_ROOT/rclone.conf}"

###

get_binding_service() {
    local binding_name="${1}"
    jq --arg b "${binding_name}" '[.[][] | select(.binding_name == $b)]' <<<"${VCAP_SERVICES}"
}

services_has_tag() {
    local services="${1}"
    local tag="${2}"
    jq --arg t "${tag}" -e '.[].tags | contains([$t])' <<<"${services}" >/dev/null
}

get_s3_service() {
    local name=${1:-"aws-s3"}
    jq --arg n "${name}" '.[$n]' <<<"${VCAP_SERVICES}"
}

get_gcs_service() {
    local name=${1:-"google-storage"}
    jq --arg n "${name}" '.[$n]' <<<"${VCAP_SERVICES}"
}

set_s3_rclone_config() {
    local config="${1}"
    local services="${2}"

    jq  -r '.[] |
"["+ .name +"]
type = s3
provider = AWS
access_key_id = "+ .credentials.ACCESS_KEY_ID +"
secret_access_key = "+ .credentials.SECRET_ACCESS_KEY +"
region = "+  (.credentials.S3_API_URL | split(".")[0] | split("s3-")[1])  +"
location_constraint = "+ (.credentials.S3_API_URL | split(".")[0] | split("s3-")[1]) +"
acl = private
env_auth = false
"' <<<"${services}" >> ${config}
}

set_gcs_rclone_config() {
    local config="${1}"
    local services="${2}"

    for s in $(jq -r '.[] | .name' <<<"${services}")
    do
        jq -r --arg n "${s}" '.[] | select(.name == $n) | .credentials.PrivateKeyData' <<<"${services}" | base64 -d > "${AUTH_ROOT}/${s}-auth.json"
    done
    jq --arg p "${AUTH_ROOT}" --arg l "${GCS_LOCATION}" -r '.[] |
"["+ .name +"]
type = google cloud storage
client_id =
client_secret =
project_number =
service_account_file = "+ $p +"/"+ .name +"-auth.json
storage_class = REGIONAL
location = "+ $l +"
"' <<<"${services}" >> ${config}
}

generate_rclone_config_from_vcap_services() {
    local rconfig="${1}"
    local binding_name="${2}"
    local service=""

    if [ -n "${binding_name}" ] && [ "${binding_name}" != "null" ]
    then
        service=$(get_binding_service "${binding_name}")
        if [ -n "${service}" ] && [ "${service}" != "null" ]
        then
            if services_has_tag "${service}" "gcp"
            then
                set_gcs_rclone_config "${rconfig}" "${service}"
            else
                set_s3_rclone_config "${rconfig}" "${service}"
            fi
        else
            return 1
        fi
    else
        service=$(get_s3_service)
        if [ -n "${service}" ] && [ "${service}" != "null" ]
        then
            set_s3_rclone_config "${rconfig}" "${service}"
        fi
        service=$(get_gcs_service)
        if [ -n "${service}" ] && [ "${service}" != "null" ]
        then
            set_gcs_rclone_config "${rconfig}" "${service}"
        fi
    fi
    return 0
}

get_bucket_from_service() {
    local s="${1}"
    local services="${2}"

    local bucket=""
    local rvalue=0

    # first, try GCS style
    bucket=$(jq -r -e --arg s "${s}" '.[][] | select(.name == $s) | .credentials.bucket_name' <<<"${services}")
    rvalue=$?
    # if empty, try S3
    if [ -z "${bucket}" ] || [ ${rvalue} -ne 0 ]
    then
        bucket=$(jq -r -e --arg s "${s}" '.[][] | select(.name == $s) | .credentials.BUCKET_NAME' <<<"${services}")
        rvalue=$?
    fi
    echo $bucket
    return $rvalue
}


random_string() {
    (
        cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${1:-32} | head -n 1 || true
    )
}


merge_vcap_services_from_file() {
    local f="${1}"
    local tempf

    if [ -r "${f}" ]
    then
        if jq type <<<$(<"${f}") > /dev/null 2>&1
        then
            tempf=$(mktemp)
            echo "${VCAP_SERVICES}" > ${tempf}
            jq -s '{"google-storage": ((.[0]."google-storage" + .[1]."google-storage") // []), "aws-s3": ((.[0]."aws-s3" + .[1]."aws-s3") // [])  }' "${f}" "${tempf}"
            rm -f ${tempf}
         else
            return 1
         fi
    else
        echo "${VCAP_SERVICES}"
    fi
    return 0
}


# exec process rclone
launch() {
    local cmd="${1}"
    shift

    local pid
    local rvalue

    if [ -n "${CLONE_SOURCE_SERVICE}" ] && ! CLONE_SOURCE_BUCKET=${CLONE_SOURCE_BUCKET:-$(get_bucket_from_service "${CLONE_SOURCE_SERVICE}" "${VCAP_SERVICES}")}
    then
        echo ">> Error, cannot find bucket on service: ${CLONE_SOURCE_SERVICE}"  >&2
        return 1
    fi
    if [ -n "${CLONE_DESTINATION_SERVICE}" ] && ! CLONE_DESTINATION_BUCKET=${CLONE_DESTINATION_BUCKET:-$(get_bucket_from_service "${CLONE_DESTINATION_SERVICE}" "${VCAP_SERVICES}")}
    then
        echo ">> Error, cannot find bucket on service: ${CLONE_DESTINATION_SERVICE}"  >&2
        return 1
    fi
    if ! [[ "${CLONE_MODE}" =~ ^(copy|sync|move)$ ]]
    then
        echo ">> Error, service '${CLONE_MODE}' not valid!, only copy|sync|move is allowed!" >&2
        return 1
    fi
    # run rclone server
    (
        echo ">> Launching pid=$$: $cmd $@"
        {
            exec $cmd $@
        } 2>&1
    ) &
    pid=$!
    sleep 20
    if ! ps -p ${pid} >/dev/null 2>&1
    then
        echo ">> Error launching: '$cmd $@'"  >&2
        return 1
    fi
    if [ -r "${AUTO_START_ACTIONS}" ]
    then
        [ -x "${AUTO_START_ACTIONS}" ] || chmod a+x "${AUTO_START_ACTIONS}"
        (
            {
                echo ">> Launching post-start pid=$$: $@"
                export CLONE_SOURCE_BUCKET="${CLONE_SOURCE_BUCKET}"
                export CLONE_DESTINATION_BUCKET="${CLONE_DESTINATION_BUCKET}"
                export RCLONE="$cmd"
                sleep 1
                ${AUTO_START_ACTIONS}
            }
        ) &
    elif [ -n "${CLONE_SOURCE_BUCKET}" ] && [ -n "${CLONE_DESTINATION_BUCKET}" ]
    then
        (
            {
                while true
                do
                    echo ">> Launching ${CLONE_MODE} job '${CLONE_SOURCE_SERVICE}:${CLONE_SOURCE_BUCKET}' -> '${CLONE_DESTINATION_SERVICE}:${CLONE_DESTINATION_BUCKET}', pid=$$"
                    sleep 1
                    $cmd -vv rc sync/${CLONE_MODE} srcFs="${CLONE_SOURCE_SERVICE}:${CLONE_SOURCE_BUCKET}" dstFs="${CLONE_DESTINATION_SERVICE}:${CLONE_DESTINATION_BUCKET}"
                    [ "${CLONE_TIMER}" == "0" ] && break || sleep ${CLONE_TIMER}
                done
            }
        ) &
    fi
    wait ${pid} 2>/dev/null
    rvalue=$?
    echo ">> Finish pid=${pid}: ${rvalue}"
    return ${rvalue}
}


run_rclone() {
    local cmd="rclone -v --config "${RCLONE_CONFIG}" --rc-addr ${RCLONE_RC_ADDR}"

    mkdir -p "${AUTH_ROOT}"
    if [ -z "${AUTH_PASSWORD}" ]
    then
        AUTH_PASSWORD=$(random_string 16)
        echo "* Generated random password for user ${AUTH_USER} in ${AUTH_ROOT}/${AUTH_USER}.password"
        echo "${AUTH_PASSWORD}" > "${AUTH_ROOT}/${AUTH_USER}.password"
    fi
    cmd="${cmd} --rc-user ${AUTH_USER} --rc-pass ${AUTH_PASSWORD}"

    if [ -r "${RCLONE_CONFIG}" ]
    then
        echo >> "${RCLONE_CONFIG}"
    else
        touch "${RCLONE_CONFIG}"
    fi
    mkdir -p $(dirname "${APP_CONFIG}")
    ln -sf "${RCLONE_CONFIG}" "${APP_CONFIG}"

    if ! VCAP_SERVICES=$(merge_vcap_services_from_file "${APP_VCAP_SERVICES}")
    then
        echo ">> Error, ${APP_VCAP_SERVICES} is not a valid json file!" >&2
        return 1
    else
        echo "$VCAP_SERVICES" > "${APP_ROOT}/VCAP_SERVICES.final"
    fi
    if ! generate_rclone_config_from_vcap_services "${RCLONE_CONFIG}" "${BINDING_NAME}"
    then
        echo ">> Error, service '${BINDING_NAME}' not found!" >&2
        return 1
    fi
    if [ "x${RCLONE_RC_SERVE}" == "xtrue" ]
    then
        launch "${cmd}" rcd --rc-web-gui --rc-serve $@
    else
        launch "${cmd}" rcd --rc-web-gui $@
    fi
}

# run
if [ -n "${CF_INSTANCE_INDEX}" ]
then
    if [ ${CF_INSTANCE_INDEX} -eq 0 ]
    then
        run_rclone $@
        exit $?
    else
        echo "ERROR, no more than 1 instance allowed with this buildpack!" >&2
        exit 1
    fi
else
    run_rclone $@
    exit $?
fi

