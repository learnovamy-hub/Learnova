import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/constants.dart';

class NotificationsScreen extends StatefulWidget {
  final VoidCallback? onRead;
  const NotificationsScreen({super.key, this.onRead});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<dynamic> _notifications = [];
  bool _loading = true;
  String _token = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString('token') ?? '';
    try {
      final r = await http.get(
        Uri.parse('$kApiUrl/api/student/notifications'),
        headers: {'Authorization': 'Bearer $_token'},
      );
      if (r.statusCode == 200) {
        setState(() => _notifications = jsonDecode(r.body)['notifications'] ?? []);
      }
    } catch (_) {}
    setState(() => _loading = false);
    // Mark all as read
    await http.patch(
      Uri.parse('$kApiUrl/api/student/notifications/read'),
      headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    widget.onRead?.call();
  }

  Future<void> _respond(String requestId, String action) async {
    try {
      final r = await http.post(
        Uri.parse('$kApiUrl/api/student/connection/respond'),
        headers: {'Authorization': 'Bearer $_token', 'Content-Type': 'application/json'},
        body: jsonEncode({'request_id': requestId, 'action': action}),
      );
      final data = jsonDecode(r.body);
      if (r.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['message'] ?? (action == 'accept' ? 'Sambungan diterima!' : 'Permintaan ditolak.')),
          backgroundColor: action == 'accept' ? kGreen : kRed,
        ));
        _load();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(data['error'] ?? 'Ralat berlaku.'),
          backgroundColor: kRed,
        ));
      }
    } catch (_) {}
  }

  Widget _buildNotification(Map<String, dynamic> n) {
    final isRequest = n['type'] == 'connection_request';
    final isRead = n['is_read'] as bool? ?? false;
    final data = n['data'] is Map ? n['data'] as Map : {};
    final requestId = data['request_id']?.toString();

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isRead ? kSurface : kSurface.withOpacity(1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isRead ? kBorder : kPrimary.withOpacity(0.4),
          width: isRead ? 1 : 1.5,
        ),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _notifColor(n['type']).withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Center(child: Icon(_notifIcon(n['type']), color: _notifColor(n['type']), size: 18)),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n['title'] ?? '', style: const TextStyle(color: kText, fontWeight: FontWeight.w700, fontSize: 13)),
            Text(_timeAgo(n['created_at']), style: const TextStyle(color: kMuted, fontSize: 11)),
          ])),
          if (!isRead) Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(color: kPrimary, shape: BoxShape.circle),
          ),
        ]),
        const SizedBox(height: 10),
        Text(n['message'] ?? '', style: const TextStyle(color: kMuted, fontSize: 13, height: 1.5)),
        if (isRequest && requestId != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => _respond(requestId, 'reject'),
              style: OutlinedButton.styleFrom(
                foregroundColor: kRed,
                side: const BorderSide(color: kRed),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Tolak', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
            const SizedBox(width: 10),
            Expanded(child: ElevatedButton(
              onPressed: () => _respond(requestId, 'accept'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kGreen,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Terima', style: TextStyle(fontWeight: FontWeight.w700)),
            )),
          ]),
        ],
      ]),
    );
  }

  IconData _notifIcon(String? type) {
    switch (type) {
      case 'connection_request': return Icons.person_add_rounded;
      case 'connection_accepted': return Icons.check_circle_rounded;
      case 'connection_rejected': return Icons.cancel_rounded;
      default: return Icons.notifications_rounded;
    }
  }

  Color _notifColor(String? type) {
    switch (type) {
      case 'connection_request': return kPrimary;
      case 'connection_accepted': return kGreen;
      case 'connection_rejected': return kRed;
      default: return kYellow;
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Baru sahaja';
    if (diff.inHours < 1) return '${diff.inMinutes} minit lalu';
    if (diff.inDays < 1) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Notifikasi', style: TextStyle(color: kText, fontWeight: FontWeight.w800)),
        iconTheme: const IconThemeData(color: kText),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: kPrimary))
          : _notifications.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.notifications_none_rounded, color: kMuted, size: 48),
                  const SizedBox(height: 12),
                  const Text('Tiada notifikasi', style: TextStyle(color: kMuted, fontSize: 15)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _notifications.length,
                  itemBuilder: (_, i) => _buildNotification(Map<String, dynamic>.from(_notifications[i])),
                ),
    );
  }
}
