import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:powersync/powersync.dart';
import '../../powersync.dart';

class StatusAppBar extends StatelessWidget implements PreferredSizeWidget {
  final Widget title;

  const StatusAppBar({super.key, required this.title});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SyncStatus>(
      stream: db.statusStream,
      initialData: db.currentStatus,
      builder: (context, snapshot) {
        final status = snapshot.data!;
        final statusIcon = _getStatusIcon(status);

        return AppBar(
          title: title,
          actions: [
            statusIcon,
            if (kDebugMode) 
              const Tooltip(
                message: 'Debug mode',
                child: Icon(Icons.developer_mode),
              ),
          ],
        );
      },
    );
  }

  Widget _getStatusIcon(SyncStatus status) {
    if (status.anyError != null) {
      if (!status.connected) {
        return const Tooltip(
          message: 'Offline',
          child: Icon(Icons.cloud_off, color: Colors.red),
        );
      } else {
        return const Tooltip(
          message: 'Sync error',
          child: Icon(Icons.sync_problem, color: Colors.orange),
        );
      }
    } else if (status.connecting) {
      return const Tooltip(
        message: 'Connecting',
        child: Icon(Icons.cloud_sync_outlined, color: Colors.blue),
      );
    } else if (!status.connected) {
      return const Tooltip(
        message: 'Not connected',
        child: Icon(Icons.cloud_off, color: Colors.grey),
      );
    } else if (status.uploading || status.downloading) {
      return const Tooltip(
        message: 'Syncing',
        child: Icon(Icons.cloud_sync_outlined, color: Colors.blue),
      );
    } else {
      return const Tooltip(
        message: 'Connected',
        child: Icon(Icons.cloud_queue, color: Colors.green),
      );
    }
  }
}