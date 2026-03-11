# Assinatura de release para Google Play

Para publicar o app na Play Store, é necessário assinar o build com uma chave de release.

## Passos

### 1. Gerar o keystore (uma vez só)

No terminal, na pasta do projeto:

```bash
# Opção A: usar o script (requer Java instalado)
chmod +x android/create_keystore.sh
./android/create_keystore.sh

# Opção B: comando manual (substitua SUA_SENHA por uma senha segura)
keytool -genkey -v -keystore upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload -storepass SUA_SENHA -keypass SUA_SENHA -dname "CN=Editai, OU=Mobile, O=Editai, L=SaoPaulo, ST=SP, C=BR"
```

O arquivo `upload-keystore.jks` será criado na raiz do projeto. **Guarde-o e as senhas em local seguro** — sem eles você não poderá atualizar o app na Play Store.

### 2. Criar key.properties

```bash
cp android/key.properties.example android/key.properties
```

Edite `android/key.properties` e substitua:
- `SUA_SENHA_DO_KEYSTORE` e `SUA_SENHA_DA_CHAVE` pela senha que você usou no passo 1
- Confirme que `storeFile=../upload-keystore.jks` está correto (caminho relativo à pasta `android/`)

### 3. Gerar o build

```bash
flutter build appbundle --release
```

O arquivo `build/app/outputs/bundle/release/app-release.aab` estará assinado em modo release e pronto para upload no Google Play Console.
