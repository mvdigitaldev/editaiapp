# Editai App

App nativo de edição de fotos com IA desenvolvido em Flutter.

## Arquitetura

O projeto segue Clean Architecture com organização por features:

- **core/**: Infraestrutura base (config, error, network, storage, utils, widgets)
- **features/**: Módulos independentes (auth, editor, gallery)
  - Cada feature contém: `data/`, `domain/`, `presentation/`
- **shared/**: Código compartilhado entre features

## Configuração

1. Instale as dependências:
```bash
flutter pub get
```

2. Configure as variáveis de ambiente do Supabase:
   - Edite `lib/core/config/app_config.dart` ou use variáveis de ambiente:
   ```bash
   flutter run --dart-define=SUPABASE_URL=sua_url --dart-define=SUPABASE_ANON_KEY=sua_key
   ```

3. Execute o app:
```bash
flutter run
```

## Estrutura do Projeto

```
lib/
├── core/                    # Infraestrutura base
├── features/                # Features do app
│   ├── auth/               # Autenticação
│   ├── editor/             # Editor de fotos
│   └── gallery/            # Galeria
├── shared/                 # Código compartilhado
└── main.dart              # Entry point
```

## Dependências Principais

- `supabase_flutter`: Integração com Supabase
- `flutter_riverpod`: Gerenciamento de estado
- `dio`: Cliente HTTP
- `flutter_secure_storage`: Armazenamento seguro
- `image_picker`: Seleção de imagens

## Próximos Passos

1. Configurar Supabase (criar projeto, tabelas, políticas RLS)
2. Implementar upload de imagens
3. Integrar com serviço de IA externo
4. Adicionar testes
