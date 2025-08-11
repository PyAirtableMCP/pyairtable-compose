#!/bin/bash

# Script to generate SSL certificates for Kafka cluster
# This creates self-signed certificates for development/testing purposes
# For production, use certificates from a trusted CA

set -e

CERT_DIR="/kafka-security"
VALIDITY_DAYS=365
KEY_SIZE=2048

echo "Generating SSL certificates for Kafka cluster..."

# Create directories if they don't exist
mkdir -p ${CERT_DIR}

# Certificate authority (CA) configuration
CA_KEY="${CERT_DIR}/ca-key"
CA_CERT="${CERT_DIR}/ca-cert"
CA_PASSWORD="pyairtable-ca-password"

# Server keystore and truststore
SERVER_KEYSTORE="${CERT_DIR}/kafka.server.keystore.jks"
SERVER_TRUSTSTORE="${CERT_DIR}/kafka.server.truststore.jks"
KEYSTORE_PASSWORD="pyairtable-keystore-password"
TRUSTSTORE_PASSWORD="pyairtable-truststore-password"
KEY_PASSWORD="pyairtable-ssl-key-password"

# Client keystore and truststore
CLIENT_KEYSTORE="${CERT_DIR}/kafka.client.keystore.jks"
CLIENT_TRUSTSTORE="${CERT_DIR}/kafka.client.truststore.jks"

echo "Step 1: Creating Certificate Authority (CA)"
openssl req -new -x509 -keyout ${CA_KEY} -out ${CA_CERT} -days ${VALIDITY_DAYS} -subj "/CN=PyAirtable-CA" -passin pass:${CA_PASSWORD} -passout pass:${CA_PASSWORD}

echo "Step 2: Creating server keystores"
for i in kafka-1 kafka-2 kafka-3; do
    echo "Creating keystore for ${i}"
    
    # Generate server keystore
    keytool -keystore ${CERT_DIR}/${i}.server.keystore.jks -alias ${i} -validity ${VALIDITY_DAYS} -genkey -keyalg RSA -keysize ${KEY_SIZE} \
        -dname "CN=${i}, OU=PyAirtable, O=PyAirtable, L=San Francisco, ST=CA, C=US" \
        -storepass ${KEYSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt
    
    # Create certificate signing request
    keytool -keystore ${CERT_DIR}/${i}.server.keystore.jks -alias ${i} -certreq -file ${CERT_DIR}/${i}.csr \
        -storepass ${KEYSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt
    
    # Sign the certificate with CA
    openssl x509 -req -CA ${CA_CERT} -CAkey ${CA_KEY} -in ${CERT_DIR}/${i}.csr -out ${CERT_DIR}/${i}-ca-signed.crt \
        -days ${VALIDITY_DAYS} -CAcreateserial -passin pass:${CA_PASSWORD}
    
    # Import CA certificate into keystore
    keytool -keystore ${CERT_DIR}/${i}.server.keystore.jks -alias CARoot -import -file ${CA_CERT} \
        -storepass ${KEYSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt
    
    # Import signed certificate into keystore
    keytool -keystore ${CERT_DIR}/${i}.server.keystore.jks -alias ${i} -import -file ${CERT_DIR}/${i}-ca-signed.crt \
        -storepass ${KEYSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt
done

echo "Step 3: Creating server truststore"
keytool -keystore ${SERVER_TRUSTSTORE} -alias CARoot -import -file ${CA_CERT} \
    -storepass ${TRUSTSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt

echo "Step 4: Creating client keystore and truststore"
# Generate client keystore
keytool -keystore ${CLIENT_KEYSTORE} -alias client -validity ${VALIDITY_DAYS} -genkey -keyalg RSA -keysize ${KEY_SIZE} \
    -dname "CN=client, OU=PyAirtable, O=PyAirtable, L=San Francisco, ST=CA, C=US" \
    -storepass ${KEYSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt

# Create client certificate signing request
keytool -keystore ${CLIENT_KEYSTORE} -alias client -certreq -file ${CERT_DIR}/client.csr \
    -storepass ${KEYSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt

# Sign client certificate with CA
openssl x509 -req -CA ${CA_CERT} -CAkey ${CA_KEY} -in ${CERT_DIR}/client.csr -out ${CERT_DIR}/client-ca-signed.crt \
    -days ${VALIDITY_DAYS} -CAcreateserial -passin pass:${CA_PASSWORD}

# Import CA certificate into client keystore
keytool -keystore ${CLIENT_KEYSTORE} -alias CARoot -import -file ${CA_CERT} \
    -storepass ${KEYSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt

# Import signed certificate into client keystore
keytool -keystore ${CLIENT_KEYSTORE} -alias client -import -file ${CERT_DIR}/client-ca-signed.crt \
    -storepass ${KEYSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt

# Create client truststore
keytool -keystore ${CLIENT_TRUSTSTORE} -alias CARoot -import -file ${CA_CERT} \
    -storepass ${TRUSTSTORE_PASSWORD} -keypass ${KEY_PASSWORD} -noprompt

echo "Step 5: Creating unified server keystores for Docker containers"
# Create unified keystore for all kafka brokers
cp ${CERT_DIR}/kafka-1.server.keystore.jks ${SERVER_KEYSTORE}

echo "Step 6: Cleaning up intermediate files"
rm -f ${CERT_DIR}/*.csr ${CERT_DIR}/*-ca-signed.crt ${CA_CERT}.srl

echo "SSL certificate generation completed!"
echo "Created files:"
echo "  - CA Certificate: ${CA_CERT}"
echo "  - Server Keystore: ${SERVER_KEYSTORE}"
echo "  - Server Truststore: ${SERVER_TRUSTSTORE}"
echo "  - Client Keystore: ${CLIENT_KEYSTORE}"
echo "  - Client Truststore: ${CLIENT_TRUSTSTORE}"
echo ""
echo "Passwords:"
echo "  - Keystore Password: ${KEYSTORE_PASSWORD}"
echo "  - Truststore Password: ${TRUSTSTORE_PASSWORD}"
echo "  - Key Password: ${KEY_PASSWORD}"
echo ""
echo "Note: These are self-signed certificates for development/testing only."
echo "For production, use certificates from a trusted Certificate Authority."