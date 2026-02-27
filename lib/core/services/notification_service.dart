// On web use stub (no dart:io); on mobile use full implementation.
export 'notification_service_stub.dart'
    if (dart.library.io) 'notification_service_impl.dart';
