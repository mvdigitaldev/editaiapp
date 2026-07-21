/// Backend FragmentProgram/Impeller — Sprint futuro.
///
/// Quando Flutter GPU estiver wired, substituir passes CPU por draw calls GPU
/// sem alterar [GpuRendererImpl] / [ShaderProgramCache].
abstract class FragmentProgramBackend {
  const FragmentProgramBackend();

  bool get isAvailable;

  Future<void> initialize();
}

/// Stub — Impeller/Metal path pendente de wiring nativo.
class FragmentProgramBackendStub implements FragmentProgramBackend {
  const FragmentProgramBackendStub();

  @override
  bool get isAvailable => false;

  @override
  Future<void> initialize() async {}
}
