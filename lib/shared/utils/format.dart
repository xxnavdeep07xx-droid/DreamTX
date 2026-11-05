/// Compact relative-time labels, e.g. "2h ago".
String timeAgo(DateTime time, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final difference = reference.difference(time);
  if (difference.isNegative || difference.inMinutes < 1) return 'Just now';
  if (difference.inMinutes < 60) return '${difference.inMinutes}m ago';
  if (difference.inHours < 24) return '${difference.inHours}h ago';
  if (difference.inDays == 1) return 'Yesterday';
  if (difference.inDays < 7) return '${difference.inDays}d ago';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${months[time.month - 1]} ${time.day}';
}

/// Human-readable byte sizes.
String formatBytes(int? bytes) {
  if (bytes == null || bytes <= 0) return 'Unknown size';
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
