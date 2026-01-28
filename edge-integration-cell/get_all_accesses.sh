#!/bin/bash

# SPDX-FileCopyrightText: 2024 SAP edge team
# SPDX-FileContributor: Kirill Satarin (@kksat)
# SPDX-FileContributor: Manjun Jiao (@mjiao)
#
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

# Determine CLI tool (KUBE_CLI env var or oc)
if [[ -n "${KUBE_CLI:-}" ]] && command -v "${KUBE_CLI}" &> /dev/null; then
    : # KUBE_CLI already set from environment
elif command -v oc &> /dev/null; then
    KUBE_CLI="oc"
elif command -v kubectl &> /dev/null; then
    KUBE_CLI="kubectl"
else
    echo "Error: Neither oc nor kubectl found in PATH"
    exit 1
fi

echo "=====================================Postgres========================================="

# Set namespace and secret name
namespace="sap-eic-external-postgres"
secret_name="eic-pguser-eic"

# Get dbhostname from the secret
dbhostname=$($KUBE_CLI get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.host}" | base64 --decode)

# Output the dbhostname
echo "External DB Hostname: $dbhostname "

# Get dbport from the secret
dbport=$($KUBE_CLI get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.port}" | base64 --decode)

# Output the dbport
echo "External DB Port: $dbport"


# Get dbname from the secret
dbname=$($KUBE_CLI get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.dbname}" | base64 --decode)

# Output the dbname
echo "External DB Name: $dbname"

# Get dbusername from the secret
dbusername=$($KUBE_CLI get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.user}" | base64 --decode)

# Output the dbusername
echo "External DB Username: $dbusername "

# Get dbpassword from the secret
dbpassword=$($KUBE_CLI get secret "$secret_name" -n "$namespace" -o jsonpath="{.data.password}" | base64 --decode)

# Output the dbpassword
echo "External DB Password: $dbpassword "

# Define variables
secret_name="pgo-root-cacert"
output_file="external_postgres_db_tls_root_cert.crt"

# Get the secret and extract the root.crt field
root_crt=$($KUBE_CLI get secret "$secret_name" -n "$namespace" -o json | jq -r '.data["root.crt"]' | base64 -d)

# Check if root_crt is not empty
if [[ -n "$root_crt" ]]; then
    # Write the content to the output file
    echo "$root_crt" > "$output_file"
    echo "External DB TLS Root Certificate saved to $output_file"
else
    echo "Error: Failed to fetch root.crt from secret $secret_name in namespace $namespace."
fi

echo "======================================Redis==========================================="

# Define the namespace, RedisEnterpriseDatabase name, and RedisEnterpriseDatabase secret field
namespace="sap-eic-external-redis"
database_name="redb"
database_secret_field="databaseSecretName"

# Get the RedisEnterpriseDatabase JSON definition and extract the databaseSecretName
secret_name=$($KUBE_CLI get RedisEnterpriseDatabase "$database_name" -n $namespace -o json | jq -r ".spec.$database_secret_field")

# Check if the secret name is empty
if [[ -z "$secret_name" ]]; then
    echo "Failed to retrieve $database_secret_field from RedisEnterpriseDatabase $database_name."
    exit 1
fi

# Get the secret and extract the password, port, and service_name
secret_data=$($KUBE_CLI get secret "$secret_name" -n "$namespace" -o json)
password=$(echo "$secret_data" | jq -r '.data["password"]' | base64 --decode)
port=$(echo "$secret_data" | jq -r '.data["port"]' | base64 --decode)
service_name=$(echo "$secret_data" | jq -r '.data["service_name"]' | base64 --decode)


service_name_with_ns="${service_name}.${namespace}.svc"
redis_server_name="rec.${namespace}.svc.cluster.local"

# Check if any of the values are empty
if [[ -z "$password" || -z "$port" || -z "$service_name" ]]; then
    echo "Failed to retrieve password, port, or service_name from secret $secret_name in namespace $namespace."
    exit 1
fi

# Get the proxy certificate content
$KUBE_CLI exec -n sap-eic-external-redis -it rec-0 -c redis-enterprise-node -- cat /etc/opt/redislabs/proxy_cert.pem > external_redis_tls_certificate.pem

echo "External Redis Addresses: $service_name_with_ns:$port"
echo "External Redis Mode: standalone"
echo "External Redis Username: [leave me blank]"
echo "External Redis Password: $password"
echo "External Redis Sentinel Username: [leave me blank]"
echo "External Redis Sentinel Password: [leave me blank]"
echo "External Redis TLS Certificate content saved to external_redis_tls_certificate.pem"
echo "External Redis Server Name: $redis_server_name"