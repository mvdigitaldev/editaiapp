#!/bin/bash
# Script para criar o keystore de release do Android.
# Execute uma vez e guarde o arquivo upload-keystore.jks e as senhas em local seguro.

set -e
cd "$(dirname "$0")/.."

KEYSTORE="upload-keystore.jks"
if [ -f "$KEYSTORE" ]; then
    echo "O arquivo $KEYSTORE já existe. Não sobrescreva se já tiver publicado o app."
    read -p "Deseja continuar mesmo assim? (s/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Ss]$ ]]; then
        exit 1
    fi
fi

echo "Criando keystore em $KEYSTORE"
echo "Você precisará informar uma senha (guarde-a em local seguro)."
keytool -genkey -v -keystore "$KEYSTORE" -keyalg RSA -keysize 2048 -validity 10000 -alias upload

echo ""
echo "Keystore criado. Agora crie android/key.properties com:"
echo "  storePassword=SUA_SENHA"
echo "  keyPassword=SUA_SENHA"
echo "  keyAlias=upload"
echo "  storeFile=../upload-keystore.jks"
echo ""
echo "Ou copie: cp android/key.properties.example android/key.properties"
echo "E edite android/key.properties com as senhas que você definiu."
