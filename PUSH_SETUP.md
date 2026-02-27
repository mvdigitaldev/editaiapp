# Configuração de Push Notifications (Editai)

## Já implementado no código

- Dependências: `firebase_core`, `firebase_messaging`, `flutter_local_notifications`
- `lib/firebase_options.dart` (substitua com `flutterfire configure`)
- `lib/core/services/notification_service.dart`
- Integração em `main.dart` e no `AuthNotifier` (login/logout)
- Rotas nomeadas usadas para deep link: `/home`, `/profile`, `/subscription`, etc.

## Passos obrigatórios

### 1. Firebase e FlutterFire

1. **Instalar o Firebase CLI** (obrigatório; o FlutterFire depende dele):
   ```bash
   npm install -g firebase-tools
   ```
   Se não tiver Node/npm, instale em https://nodejs.org ou use: `curl -sL https://firebase.tools | bash`
2. **Instalar o FlutterFire CLI:**
   ```bash
   dart pub global activate flutterfire_cli
   ```
3. **Garantir que o comando `flutterfire` está no PATH.** Se ao rodar `flutterfire` der "comando não encontrado", adicione ao seu shell (ex.: `~/.zshrc`):
   ```bash
   export PATH="$PATH:$HOME/.pub-cache/bin"
   ```
   Depois abra um novo terminal ou rode `source ~/.zshrc`.
4. **Configurar o Firebase no projeto:** abra o terminal na pasta do projeto (`editaiapp`) e rode:
   ```bash
   cd /caminho/para/editaiapp
   flutterfire configure
   ```
   - O comando abre o navegador para você fazer login no Google (se ainda não estiver logado) e escolher ou criar um projeto Firebase.
   - Ao final, ele gera/atualiza o arquivo `lib/firebase_options.dart` e pode baixar `GoogleService-Info.plist` (iOS) e `google-services.json` (Android, se existir a pasta `android/`).
   - **Se você já tem um projeto Firebase:** use `flutterfire configure --project=SEU_PROJECT_ID -y --platforms=ios,android` (substitua `SEU_PROJECT_ID` pelo ID do projeto, ex.: `editai-3d616`). Use o PATH completo se precisar: `$HOME/.pub-cache/bin/flutterfire configure --project=editai-3d616 -y --platforms=ios,android`.

### 2. iOS

1. No Firebase Console, adicione um app iOS com o Bundle ID do app (ex.: do Xcode em Runner > Signing).
2. Baixe `GoogleService-Info.plist` e coloque em `ios/Runner/`.
3. No Xcode: **Signing & Capabilities** > **+ Capability** > **Push Notifications**.
4. Opcional: **Background Modes** > marque **Remote notifications**.

### 3. Android (quando houver pasta `android/`)

1. No Firebase Console, adicione um app Android com o package name do app.
2. Baixe `google-services.json` e coloque em `android/app/`.
3. Em `android/build.gradle` (raiz), em `dependencies`:
   - `classpath 'com.google.gms:google-services:4.4.2'`
4. Em `android/app/build.gradle`:
   - No topo: `id "com.google.gms.google-services"`
   - No final do arquivo: `apply plugin: 'com.google.gms.google-services'`
5. Em `android/app/src/main/AndroidManifest.xml`:
   - Permissão: `<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>`
   - Dentro de `<application>`:
   ```xml
   <service
       android:name="com.google.firebase.messaging.FirebaseMessagingService"
       android:exported="false">
       <intent-filter>
           <action android:name="com.google.firebase.MESSAGING_EVENT" />
       </intent-filter>
   </service>
   ```

### 4. Supabase

Execute a migration `supabase/migrations/20250226100000_create_device_tokens.sql` (via `supabase db push` ou copiando o SQL no Supabase Dashboard > SQL Editor) para criar a tabela `device_tokens` e a função RPC `save_device_token`.

Para enviar notificações (opcional): crie uma Edge Function que use a Firebase Admin SDK (secret `FIREBASE_SERVICE_ACCOUNT_JSON`) e leia os tokens da tabela `device_tokens`.
