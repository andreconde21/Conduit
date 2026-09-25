import 'package:conduit/features/live_preview/domain/dev_server_detection.dart';
import 'package:conduit/features/live_preview/presentation/preview_ready_controller.dart';
import 'package:flutter/material.dart';

/// "Preview ready · :5173 · vite": one tap opens Live preview on that port,
/// the × dismisses it for the session. Collapses to nothing without an
/// offer, or while [hidden] says the offer is already on screen.
class PreviewReadyChip extends StatelessWidget {
  const PreviewReadyChip({
    required this.controller,
    required this.onOpen,
    this.hidden,
    super.key,
  });

  final PreviewReadyController controller;

  /// Opens Live preview on the offer's port and path.
  final ValueChanged<DevServerOffer> onOpen;

  /// True for an offer that needs no chip (Live preview already shows it).
  final bool Function(DevServerOffer offer)? hidden;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final offer = controller.offer;
        if (offer == null || (hidden?.call(offer) ?? false)) {
          return const SizedBox.shrink();
        }
        final scheme = Theme.of(context).colorScheme;
        return Material(
          key: const ValueKey('preview-ready-chip'),
          color: scheme.primaryContainer,
          elevation: 3,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () {
                  controller.markOpened();
                  onOpen(offer);
                },
                child: Tooltip(
                  message: offer.cwd == null
                      ? 'Open in Live preview'
                      : 'Open in Live preview (${offer.cwd})',
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 7, 4, 7),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.public_rounded,
                          size: 16,
                          color: scheme.onPrimaryContainer,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: Text(
                            offer.chipText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onPrimaryContainer,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                key: const ValueKey('preview-ready-dismiss'),
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                iconSize: 16,
                color: scheme.onPrimaryContainer,
                icon: const Icon(Icons.close_rounded),
                onPressed: controller.dismiss,
              ),
            ],
          ),
        );
      },
    );
  }
}
