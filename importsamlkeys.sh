#!/bin/bash
SCRIPT_HOME=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
STRONGKEY_HOME=/usr/local/strongkey
SKFS_HOME=$STRONGKEY_HOME/skfs

DID=${1}
SAML_KEYSTORE_PASS=${2}
SAML_EXTERNAL_STORETYPE=${3}
SAML_EXTERNAL_STOREPATH=${4}
SAML_EXTERNAL_STOREPASS=${5}
SAML_EXTERNAL_CERT_ALIAS=${6}
SAML_EXTERNAL_KEY_ALIAS=${7}
SAML_EXTERNAL_KEY_PASS=${8}

function check_exists {
        for ARG in "$@"
        do
            if [ ! -f $ARG ]; then
                >&2 echo -e "\E[31m$ARG Not Found. Check to ensure the file exists in the proper location and try again.\E[0m"
                exit 1
            fi
        done
}

# Checks
check_exists $SAML_EXTERNAL_STOREPATH

# Make backup of existing SKFS SSO keystore
if [ -f $SKFS_HOME/keystores/ssosigningkeystore.bcfks ]; then
        cp $SKFS_HOME/keystores/ssosigningkeystore.bcfks $SKFS_HOME/keystores/ssosigningkeystore.bcfks.bak
fi
if [ -f $SKFS_HOME/keystores/ssosigningtruststore.bcfks ]; then
        cp $SKFS_HOME/keystores/ssosigningtruststore.bcfks $SKFS_HOME/keystores/ssosigningtruststore.bcfks.bak
fi

IFS=',' read -r -a SAMLKeyAliasArray <<< "$SAML_EXTERNAL_KEY_ALIAS" # Convert provided key aliases into an array variable
IFS=',' read -r -a SAMLCertAliasArray <<< "$SAML_EXTERNAL_CERT_ALIAS" # Convert provided cert aliases into an array variable

for (( COUNT = 1 ; COUNT <= $SAML_CERTS_PER_SERVER ; COUNT++ )); do
        # Delete existing aliases to make room for new aliases
        keytool -delete -alias samlsigning-$DID-$COUNT -keystore $SKFS_HOME/keystores/ssosigningkeystore.bcfks -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $STRONGKEY_HOME/keymanager/lib/bc-fips-1.0.2.1.jar -storepass $SAML_KEYSTORE_PASS
        keytool -delete -alias samlsigning-$DID-$COUNT -keystore $SKFS_HOME/keystores/ssosigningtruststore.bcfks -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $STRONGKEY_HOME/keymanager/lib/bc-fips-1.0.2.1.jar -storepass $SAML_KEYSTORE_PASS
        # Add new aliases with provided SAML key/cert
        keytool -importkeystore -noprompt -srckeystore $SAML_EXTERNAL_STOREPATH -srcstorepass $SAML_EXTERNAL_STOREPASS -alias ${SAMLKeyAliasArray[(($COUNT-1))]} -srckeypass $SAML_EXTERNAL_KEY_PASS -srcstoretype $SAML_EXTERNAL_STORETYPE -destkeystore $SKFS_HOME/keystores/ssosigningkeystore.bcfks -deststorepass $SAML_KEYSTORE_PASS -destalias samlsigning-$DID-$COUNT -destkeypass $SAML_KEYSTORE_PASS -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $STRONGKEY_HOME/keymanager/lib/bc-fips-1.0.2.1.jar
        keytool -importkeystore -noprompt -srckeystore $SAML_EXTERNAL_STOREPATH -srcstorepass $SAML_EXTERNAL_STOREPASS -alias ${SAMLCertAliasArray[(($COUNT-1))]} -srcstoretype $SAML_EXTERNAL_STORETYPE -destkeystore $SKFS_HOME/keystores/ssosigningtruststore.bcfks -deststorepass $SAML_KEYSTORE_PASS -destalias samlsigning-$DID-$COUNT -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $STRONGKEY_HOME/keymanager/lib/bc-fips-1.0.2.1.jar
        #signandverify newly imported key/cert
        java -jar $STRONGKEY_HOME/keymanager/keymanager.jar verifysigningkeys $SKFS_HOME/keystores/ssosigningkeystore.bcfks $SKFS_HOME/keystores/ssosigningtruststore.bcfks $SAML_KEYSTORE_PASS samlsigning-$DID-$COUNT RSA
        verifystatus=$?
        if [ $verifystatus -ne 0 ]; then
                echo "Error encountered while verifying key/cert entry imported SAML signing keys."
                exit $verifystatus
        fi
done

exit 0
