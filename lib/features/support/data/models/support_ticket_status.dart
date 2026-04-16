class SupportTicketStatus {
  static const String novo = 'NOVO';
  static const String aberto = 'ABERTO';
  static const String aguardandoCliente = 'AGUARDANDO_CLIENTE';
  static const String respondido = 'RESPONDIDO';
  static const String fechado = 'FECHADO';

  static const List<String> values = [
    novo,
    aberto,
    aguardandoCliente,
    respondido,
    fechado,
  ];

  static String label(String status) {
    switch (status) {
      case novo:
        return 'Novo';
      case aberto:
        return 'Aberto';
      case aguardandoCliente:
        return 'Aguardando cliente';
      case respondido:
        return 'Respondido';
      case fechado:
        return 'Fechado';
      default:
        return status;
    }
  }
}
