TEMP_DIR=$(mktemp -d)

kubectl get secret example-clusterissuer -ojsonpath='{.data.ca\.crt}' | base64 -D > ${TEMP_DIR}/ca.crt
openssl x509 -in ${TEMP_DIR}/ca.crt -text -noout

kubectl get secret example-clusterissuer -ojsonpath='{.data.tls\.crt}' | base64 -D > ${TEMP_DIR}/tls.crt
openssl x509 -in ${TEMP_DIR}/tls.crt -text -noout
