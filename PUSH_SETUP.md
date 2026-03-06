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

---

## Notificação ao ganhar créditos

Quando o usuário recebe créditos (insert em `credit_transactions` com `amount > 0`), o app envia uma push notification.

### Backend (Supabase)

1. **Edge Function `notify-credit-earned`**
   - Deploy: `supabase functions deploy notify-credit-earned`
   - Variáveis de ambiente (Supabase Dashboard > Edge Functions > notify-credit-earned > Settings):
     - `FIREBASE_SERVICE_ACCOUNT_JSON`: JSON completo da conta de serviço do Firebase (Project settings > Service accounts > Generate new private key). Cole o conteúdo do arquivo JSON como string.
     - `NOTIFY_CREDITS_INVOCATION_SECRET`: um segredo compartilhado (ex.: string aleatória longa). O **mesmo valor** deve ser guardado no Vault (passo abaixo). A função usa `SUPABASE_SERVICE_ROLE_KEY` das secrets do Supabase; não é necessário configurá-la manualmente.

2. **Extensão pg_net, trigger e Vault**
   - Execute as migrations `20260324120000_notify_credit_earned_trigger.sql` e `20260325120000_notify_credit_earned_use_vault.sql`.
   - No Dashboard: Database > Extensions > habilite **pg_net** (e **Vault**, se ainda não estiver).
   - No **Vault** (Dashboard > Database > Vault): crie um secret com **name** `notify_credits_invocation_secret` e **valor** igual ao que você definiu em `NOTIFY_CREDITS_INVOCATION_SECRET` na Edge Function.
   - Em `app_settings` (via SQL ou Dashboard), configure apenas a URL:
     - `notify_credit_earned_url`: `https://SEU_PROJECT_REF.supabase.co/functions/v1/notify-credit-earned`
   - **Não** guarde a Service Role Key na tabela; o trigger usa o segredo do Vault e a Edge Function usa a `SUPABASE_SERVICE_ROLE_KEY` das suas secrets.

### App (Flutter)

- Ao tocar na notificação de créditos, o app abre a tela **Créditos Extra** (`/credits-shop`) via deep link. Nenhuma alteração extra é necessária no código.

---

## Notificação ao atualizar plano

Quando o plano do usuário é alterado (`current_plan_id` na tabela `users` é atualizado), o app envia uma push notification informando o novo plano.

### Backend (Supabase)

1. **Edge Function `notify-plan-updated`**
   - Deploy: `supabase functions deploy notify-plan-updated`
   - Variáveis de ambiente (Supabase Dashboard > Edge Functions > notify-plan-updated > Settings):
     - `FIREBASE_SERVICE_ACCOUNT_JSON`: mesmo JSON da conta de serviço usado em `notify-credit-earned`
     - `NOTIFY_PLAN_UPDATED_INVOCATION_SECRET`: segredo compartilhado (ex.: string aleatória longa). O **mesmo valor** deve ser guardado no Vault (passo abaixo). A função usa `SUPABASE_SERVICE_ROLE_KEY` e `SUPABASE_URL` das secrets do Supabase.

2. **Trigger e Vault**
   - Execute a migration `20260328120000_notify_plan_updated_trigger.sql`.
   - No **Vault** (Dashboard > Database > Vault): crie um secret com **name** `notify_plan_updated_invocation_secret` e **valor** igual ao que você definiu em `NOTIFY_PLAN_UPDATED_INVOCATION_SECRET` na Edge Function.
   - Em `app_settings` (via SQL ou Dashboard), configure a URL:
     - `notify_plan_updated_url`: `https://SEU_PROJECT_REF.supabase.co/functions/v1/notify-plan-updated`

### App (Flutter)

- Ao tocar na notificação de plano atualizado, o app abre a tela **Assinatura** (`/subscription`) via deep link. Nenhuma alteração extra é necessária no código.
