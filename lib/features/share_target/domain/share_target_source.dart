import 'package:conduit/features/share_target/domain/shared_payload.dart';

/// Delivers payloads the OS shared into the app.
abstract class ShareTargetSource {
  /// Payloads shared while the app runs.
  Stream<SharedPayload> get shares;

  /// Payloads queued before Dart was listening (cold start).
  Future<List<SharedPayload>> takePending();
}
