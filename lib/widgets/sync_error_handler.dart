import 'package:flutter/material.dart';
import '../models/sync_error.dart';
import '../services/sync/sync_service.dart';

/// 同步错误处理器 Widget
/// 监听同步错误并显示友好的错误提示
class SyncErrorHandler extends StatefulWidget {
  final SyncService syncService;
  final Widget child;

  const SyncErrorHandler({
    Key? key,
    required this.syncService,
    required this.child,
  }) : super(key: key);

  @override
  State<SyncErrorHandler> createState() => _SyncErrorHandlerState();
}

class _SyncErrorHandlerState extends State<SyncErrorHandler> {
  @override
  void initState() {
    super.initState();
    // 监听错误流
    widget.syncService.errorStream.listen(_handleError);
  }

  void _handleError(SyncError error) {
    // 只显示需要显示给用户的错误
    if (!error.shouldShowToUser()) {
      return;
    }

    // 根据错误严重程度选择不同的显示方式
    if (error.isRecoverable) {
      _showErrorSnackBar(error);
    } else {
      _showErrorDialog(error);
    }
  }

  void _showErrorSnackBar(SyncError error) {
    if (!mounted) return;

    final snackBar = SnackBar(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            error.getUserFriendlyMessage(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            error.getSuggestion(),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      backgroundColor: _getErrorColor(error.type),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(
        label: '知道了',
        textColor: Colors.white,
        onPressed: () {
          ScaffoldMessenger.of(context).hideCurrentSnackBar();
        },
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(snackBar);
  }

  void _showErrorDialog(SyncError error) {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.error_outline,
              color: _getErrorColor(error.type),
            ),
            const SizedBox(width: 8),
            const Text('同步错误'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              error.getUserFriendlyMessage(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 12),
            Text(error.getSuggestion()),
            if (error.details != null) ...[
              const SizedBox(height: 12),
              Text(
                '详细信息：',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                error.details!,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('知道了'),
          ),
        ],
      ),
    );
  }

  Color _getErrorColor(SyncErrorType type) {
    switch (type) {
      case SyncErrorType.networkUnavailable:
      case SyncErrorType.connectionTimeout:
      case SyncErrorType.connectionFailed:
        return Colors.orange;
      case SyncErrorType.dataCorrupted:
      case SyncErrorType.permissionDenied:
        return Colors.red;
      case SyncErrorType.deviceNotFound:
      case SyncErrorType.deviceOffline:
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
