#!/bin/bash
SCRIPT_HOME=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# Inputs with some default values
DN="" # Default is set later after DID is set
DID=""
CERT_VALIDITY=365
JWT_CREATE=false
JWT_CN_LIST="CN=SKFS JWT Signer 1,CN=SKFS JWT Signer 2,CN=SKFS JWT Signer 3"
JWT_KEY_ALGORITHM=EC
JWT_KEY_SIZE=512
SAML_CREATE=false
SAML_CN_LIST="CN=SKFS SAML Signer 1,CN=SKFS SAML Signer 2,CN=SKFS SAML Signer 3"
SAML_KEY_ALGORITHM=RSA
SAML_KEY_SIZE=2048
KEYSTORE_PASS=Abcd1234!
DISABLE_FIPS_FLAG_OPTION=
KEYSTORE_PATH=/usr/local/strongkey/skfs/keystores

# Other vars
KEYMANAGER_HOME=$SCRIPT_HOME/keymanager
BCFIPS_PATH=$KEYMANAGER_HOME/lib/bc-fips-1.0.2.1.jar
SSO_KEYSTORE_PATH=$KEYSTORE_PATH/ssosigningkeystore.bcfks
SSO_TRUSTSTORE_PATH=$KEYSTORE_PATH/ssosigningtruststore.bcfks

usage="
SYNOPSIS
        keygen-sso.sh -did <Domain ID> [-jwt] [-saml] [-h | --help] [-dn <DN>] [-cs <Cluster Size>] [-v <Certificate Validity>] [-p <Keystore Password>] [-o <Output Path>] [options]

DESCRIPTION
        This script creates a Root Certificate Authority for the specified domain as well as a set of jwt, saml, or both leaf certificates signed by the Root CA.

OPTIONS
        -h, --help
                Displays this help message.

        -dn, --distinguished-name
                Defaut: \"$DN\"
                Determines the JWT or SAML leaf certificates' DN on creation: \"CN=[ JWT | SAML ] Signing Certificate \$DID-\$COUNT, \$DN\"

        -did, --domainid
                Determines the domain ID that the JWT/SAML keys and certificates will be created for.

        -v, --validity
                Default: $CERT_VALIDITY
                Determines the number of days the JWT/SAML leaf keys and certificates will be valid for.

        -jwt
                If specified, creates JWT signing keys and certificates and stores them in the sso keystore/truststore

        -jwtcns, --jwt-common-names
                Default: CN=JWT Signing Certificate \$DID-1,CN=JWT Signing Certificate \$DID-2,CN=JWT Signing Certificate \$DID-3
                Determines the JWT certificate common names and number of certificates created for this domain.

        -jwtalg, --jwt-algorithm
                Default: $JWT_KEY_ALGORITHM
                Determines the key algorithm for the JWT keys.

        -jwtks, --jwt-key-size
                Default: $JWT_KEY_SIZE
                Determines the key size for the JWT keys.

        -saml
                If specified, creates SAML signing keys and certificates and stores them in the sso keystore/truststore

        -samlcns, --saml-common-names
                Default: CN=SAML Signing Certificate \$DID-1,CN=SAML Signing Certificate \$DID-2,CN=SAML Signing Certificate \$DID-3
                Determines the SAML certificate common names and number of certificates created for this domain.

        -samlalg, --saml-algorithm
                Default: $SAML_KEY_ALGORITHM
                Determines the key algorithm for the SAML keys.

        -samlks, --saml-key-size
                Default: $SAML_KEY_SIZE
                Determines the key size for the SAML keys.

        -p, --keystore-password
                Default: $KEYSTORE_PASS
                Determines the password for all created keystores (CA key pair, JWT key pair, SAML key pair, ssosigningkeystore)

        -o, --output-path
                Default: $KEYSTORE_PATH
                Determines the path on the file system where the ssosigningkeystore.bcfks and ssosigningtruststore.bcfks will be created. Relative path may be used.

        -nf, --no-fips
                Default: $profile
                Profile options: $all_profiles
                Profile used to build the SAKA distribution.
"


# Option handling
while [[ "$1" =~ ^- && ! "$1" == "--" ]]; do case $1 in
        -h | --help )
                echo "$usage"
                exit 0
                ;;
        -dn | --distinguished-name )
                shift;
                DN="$1"
                ;;
        -did | --domainid)
                shift;
                DID="$1"
                if [ -z $DN ]; then
                        DN="OU=DID $DID, O=StrongKey"
                fi
                ;;
        -v | --validity )
                shift;
                CERT_VALIDITY="$1"
                ;;
        -jwt )
                JWT_CREATE=true
                ;;
        -jwtcns | --jwt-common-names )
                shift;
                JWT_CN_LIST="$1"
                ;;
        -jwtalg | --jwt-algorithm )
                shift;
                JWT_KEY_ALGORITHM="$1"
                ;;
        -jwtks | --jwt-key-size )
                shift;
                JWT_KEY_SIZE="$1"
                ;;
        -saml )
                SAML_CREATE=true
                ;;
        -samlcns | --saml-common-names )
                shift;
                SAML_CN_LIST="$1"
                ;;
        -samlalg | --saml-algorithm )
                shift;
                SAML_KEY_ALGORITHM="$1"
                ;;
        -samlks | --saml-key-size )
                shift;
                SAML_KEY_SIZE="$1"
                ;;
        -p | --keystore-password )
                shift;
                KEYSTORE_PASS="$1"
                ;;
        -o | --output-path )
                shift;
                KEYSTORE_PATH=$(realpath "$1")
                SSO_KEYSTORE_PATH=$KEYSTORE_PATH/ssosigningkeystore.bcfks
                SSO_TRUSTSTORE_PATH=$KEYSTORE_PATH/ssosigningtruststore.bcfks
                ;;
        -nf | --no-fips )
                DISABLE_FIPS_FLAG_OPTION="-J-Dcom.redhat.fips=false"
                ;;
esac; shift; done
if [[ "$1" == '--' ]]; then shift; fi

if [[ "${JWT_CREATE,,}" = "false" && "${SAML_CREATE,,}" = "false" ]]; then
        echo "No -jwt or -saml flag specified. Please use the --help flag to see usage."
        exit 0
fi

mkdir -p sso-keys

# Create the Root Certificate Authority (CA)

# If the CA for this domain already exists in the keystore located at $SSO_KEYSTORE_PATH, use that CA instead of creating a new one.
if [[ -f $SSO_KEYSTORE_PATH ]]; then
        keytool -list -alias ssoca-$DID -keystore $SSO_KEYSTORE_PATH -storepass $KEYSTORE_PASS -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $BCFIPS_PATH >/dev/null
        if [ $? -eq 0 ]; then
                CA_EXISTS=true
        fi
fi

if [ "$CA_EXISTS" = "true" ]; then
        echo "Root CA for domain $DID exists in keystore located at $SSO_KEYSTORE_PATH. Skipping Root CA generation."
        echo
else
        # Generate self-signed root CA key pair and extract cert to file
        echo "Generating Root CA for domain $DID..."
        keytool -genkeypair -alias ssoca-$DID -keystore sso-keys/ssoca-$DID.jks -storetype JKS -storepass $KEYSTORE_PASS -keypass $KEYSTORE_PASS -keyalg EC -groupname secp521r1 -sigalg SHA512withECDSA -validity $CERT_VALIDITY -dname "CN=StrongKey FIDO Server RootCA, $DN" -ext BasicConstraints:critical=ca:true -ext KeyUsage:critical=keyCertSign,cRLSign >/dev/null 2>&1
        keytool -exportcert -rfc -alias ssoca-$DID -keystore sso-keys/ssoca-$DID.jks -storepass $KEYSTORE_PASS -storetype JKS -file sso-keys/ssoca-$DID.pem >/dev/null 2>&1

        echo "Storing Root CA into keystores..."
        # Import CA key into BCFKS keystore
        keytool -importkeystore -deststorepass $KEYSTORE_PASS -destkeystore $SSO_KEYSTORE_PATH -srckeystore sso-keys/ssoca-$DID.jks -srcstorepass $KEYSTORE_PASS -srcstoretype JKS -noprompt -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $BCFIPS_PATH
        # Import CA cert into BCFKS truststore
        keytool -import -alias ssoca-$DID -file sso-keys/ssoca-$DID.pem -keystore $SSO_TRUSTSTORE_PATH -storepass $KEYSTORE_PASS -noprompt -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $BCFIPS_PATH -trustcacerts

        echo "RootCA generation finished!"
        echo
fi

if [ ${JWT_CREATE,,} = "true" ]; then

        # Create the JWT signing keys and certificates
        COUNT=1
        IFS=','
        read -a cnarray <<< "$JWT_CN_LIST"
        for cn in "${cnarray[@]}";
        do
                echo "Generating JWT signing key for $cn for domain $DID..."
                # Generate JWT signing key pair
                keytool -genkeypair -alias jwtsigning-$DID-$COUNT -keystore sso-keys/jwtsigningkey-$DID-$COUNT.jks -storetype JKS -storepass $KEYSTORE_PASS -keypass $KEYSTORE_PASS -keyalg EC -groupname secp256r1 -sigalg SHA256withECDSA -validity $CERT_VALIDITY -dname "$cn, $DN" >/dev/null 2>&1
                # Create Certificate Signing Request and sign with CA, resulting in JWT signing certificate
                keytool -keystore sso-keys/jwtsigningkey-$DID-$COUNT.jks -storepass $KEYSTORE_PASS -certreq -alias jwtsigning-$DID-$COUNT -keyalg EC 2>/dev/null | keytool -gencert -rfc -alias ssoca-$DID -keystore sso-keys/ssoca-$DID.jks -storetype JKS -validity $CERT_VALIDITY -storepass $KEYSTORE_PASS > sso-keys/jwtsigning-$DID-$COUNT.pem 2>/dev/null
                # Import the rootCA into the individual jks
                keytool -import -file sso-keys/ssoca-$DID.pem -keystore sso-keys/jwtsigningkey-$DID-$COUNT.jks -storepass $KEYSTORE_PASS -alias ssoca-$DID -noprompt >/dev/null 2>&1
                # Import the newly signed certificate in the jks file
                keytool -import -file sso-keys/jwtsigning-$DID-$COUNT.pem -keystore sso-keys/jwtsigningkey-$DID-$COUNT.jks -storepass $KEYSTORE_PASS -alias jwtsigning-$DID-$COUNT -noprompt >/dev/null 2>&1
                # DELETE the rootCA into the individual jks
                keytool -delete -keystore sso-keys/jwtsigningkey-$DID-$COUNT.jks -storepass $KEYSTORE_PASS -alias ssoca-$DID -noprompt >/dev/null 2>&1
                # Import JWT signing key into signing keystore
                keytool -importkeystore -deststorepass $KEYSTORE_PASS -destkeystore $SSO_KEYSTORE_PATH -srckeystore sso-keys/jwtsigningkey-$DID-$COUNT.jks -srcstorepass $KEYSTORE_PASS -srcstoretype JKS -noprompt -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $BCFIPS_PATH $DISABLE_FIPS_FLAG_OPTION
                # Import JWT signing certificate into signingtruststore
                keytool -import -alias jwtsigning-$DID-$COUNT -file sso-keys/jwtsigning-$DID-$COUNT.pem -keystore $SSO_TRUSTSTORE_PATH -storepass $KEYSTORE_PASS -noprompt -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $BCFIPS_PATH
                # Test signing and verifying newly created JWT key/cert
                java -jar $SCRIPT_HOME/keymanager/keymanager.jar verifysigningkeys $SSO_KEYSTORE_PATH $SSO_TRUSTSTORE_PATH $KEYSTORE_PASS jwtsigning-$DID-$COUNT EC
                verifystatus=$?
                if [ $verifystatus -ne 0 ]; then
                        echo "Error encountered while verifying key/cert entry imported JWT signing keys."
                        exit $verifystatus
                fi
                COUNT=$((COUNT+1))
        done

        echo "JWT signing keys generation finished!"
        echo
fi

if [ ${SAML_CREATE,,} = "true" ]; then

        # Create the SAML signing keys and certificates
        COUNT=1
        IFS=','
        read -a cnarray <<< "$SAML_CN_LIST"
        for cn in "${cnarray[@]}";
        do
                echo "Generating SAML signing key for $cn for domain $DID..."
                # Generate SAML signing key pair
                keytool -genkey -alias samlsigning-$DID-$COUNT -keystore sso-keys/samlsigning-$DID-$COUNT.jks -storetype JKS -storepass $KEYSTORE_PASS -keypass $KEYSTORE_PASS -keyalg RSA -keysize 2048 -sigalg SHA256withRSA -validity $CERT_VALIDITY -dname "$cn, $DN" >/dev/null 2>&1
                # Create Certificate Signing Request and sign with CA, resulting in SAML signing certificate
                keytool -keystore sso-keys/samlsigning-$DID-$COUNT.jks -storepass $KEYSTORE_PASS -certreq -alias samlsigning-$DID-$COUNT -keyalg RSA 2>/dev/null | keytool -gencert -rfc -alias ssoca-$DID -keystore sso-keys/ssoca-$DID.jks -storetype JKS -validity $CERT_VALIDITY -storepass $KEYSTORE_PASS -ext ku:c=dig > sso-keys/samlsigning-$DID-$COUNT.pem 2>/dev/null
                # Import the rootCA into the individual jks
                keytool -import -file sso-keys/ssoca-$DID.pem -keystore sso-keys/samlsigning-$DID-$COUNT.jks -storepass $KEYSTORE_PASS -alias ssoca-$DID -noprompt >/dev/null 2>&1
                # Import the newly signed certificate in the jks file
                keytool -import -file sso-keys/samlsigning-$DID-$COUNT.pem -keystore sso-keys/samlsigning-$DID-$COUNT.jks -storepass $KEYSTORE_PASS -alias samlsigning-$DID-$COUNT -noprompt >/dev/null 2>&1
                # DELETE the rootCA into the individual jks
                keytool -delete -keystore sso-keys/samlsigning-$DID-$COUNT.jks -storepass $KEYSTORE_PASS -alias ssoca-$DID -noprompt >/dev/null 2>&1
                # Import SAML signing key into signing keystore
                keytool -importkeystore -deststorepass $KEYSTORE_PASS -destkeystore $SSO_KEYSTORE_PATH -srckeystore sso-keys/samlsigning-$DID-$COUNT.jks -srcstorepass $KEYSTORE_PASS -srcstoretype JKS -noprompt -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $BCFIPS_PATH $DISABLE_FIPS_FLAG_OPTION
                # Import SAML signing certificate into signingtruststore
                keytool -import -alias samlsigning-$DID-$COUNT -file sso-keys/samlsigning-$DID-$COUNT.pem -keystore $SSO_TRUSTSTORE_PATH -storepass $KEYSTORE_PASS -noprompt -storetype BCFKS -providername BCFIPS -providerclass org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -provider org.bouncycastle.jcajce.provider.BouncyCastleFipsProvider -providerpath $BCFIPS_PATH
                # Test signing and verifying newly created SAML key/cert
                java -jar $SCRIPT_HOME/keymanager/keymanager.jar verifysigningkeys $SSO_KEYSTORE_PATH $SSO_TRUSTSTORE_PATH $KEYSTORE_PASS samlsigning-$DID-$COUNT RSA
                verifystatus=$?
                if [ $verifystatus -ne 0 ]; then
                        echo "Error encountered while verifying key/cert entry imported SAML signing keys."
                        exit $verifystatus
                fi
                COUNT=$((COUNT+1))
        done

        echo "SAML signing keys generation finished!"
        echo
fi

exit 0
