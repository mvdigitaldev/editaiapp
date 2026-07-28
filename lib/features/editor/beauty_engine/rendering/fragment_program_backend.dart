import '../body_reshape/rendering/fragment_program_warp_backend.dart';

/// Backend FragmentProgram/Impeller para preview GPU.
abstract class FragmentProgramBackend {
  const FragmentProgramBackend();

  bool get isAvailable;

  Future<void> initialize();
}

/// Stub legado — Impeller indisponível / testes sem GPU.
class FragmentProgramBackendStub implements FragmentProgramBackend {
  const FragmentProgramBackendStub();

  @override
  bool get isAvailable => false;

  @override
  Future<void> initialize() async {}
}

/// Factory do backend de warp preview (Sprint 9).
FragmentProgramBackend createDefaultFragmentProgramBackend({
  bool forceCpuFallback = false,
}) {
  return FragmentProgramWarpBackend(forceCpuFallback: forceCpuFallback);
}
