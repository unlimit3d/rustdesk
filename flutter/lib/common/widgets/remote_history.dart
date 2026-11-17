import 'dart:convert';

import 'package:flutter/material.dart';

import '../../common.dart';
import '../../models/peer_model.dart';
import '../../models/platform_model.dart';

class RemoteHistoryEntry {
  final String id;
  final int time;
  const RemoteHistoryEntry(this.id, this.time);
}

List<RemoteHistoryEntry> decodeRemoteHistory(String source) {
  final data = jsonDecode(source) as Map<String, dynamic>;
  if (data['error'] != null) throw FormatException(data['error'].toString());
  final history = data['history'] as Map<String, dynamic>;
  final entries = <RemoteHistoryEntry>[];
  for (final peer in history.entries) {
    for (final time in (peer.value as List).cast<int>()) {
      entries.add(RemoteHistoryEntry(peer.key, time));
    }
  }
  entries.sort((a, b) => b.time.compareTo(a.time));
  return entries;
}

void showAllRemoteHistory(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => const _RemoteHistoryDialog(),
  );
}

class _RemoteHistoryDialog extends StatefulWidget {
  const _RemoteHistoryDialog();

  @override
  State<_RemoteHistoryDialog> createState() => _RemoteHistoryDialogState();
}

class _RemoteHistoryDialogState extends State<_RemoteHistoryDialog> {
  late final Future<List<RemoteHistoryEntry>> _history;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _history =
        bind.mainGetCommon(key: 'remote-history').then(decodeRemoteHistory);
  }

  String _name(String id) {
    for (final peer in gFFI.recentPeersModel.peers) {
      if (peer.id == id) {
        return peer.alias.isNotEmpty ? peer.alias : peer.hostname;
      }
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(translate('Remote history')),
      content: SizedBox(
        width: 620,
        height: 420,
        child: Column(
          children: [
            TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: translate('Search'),
              ),
              onChanged: (value) =>
                  setState(() => _search = value.toLowerCase()),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<RemoteHistoryEntry>>(
                future: _history,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Center(
                        child: SelectableText(
                            '${translate('Error')}: ${snapshot.error}'));
                  }
                  if (!snapshot.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final entries = snapshot.data!
                      .where((entry) => '${entry.id} ${_name(entry.id)}'
                          .toLowerCase()
                          .contains(_search))
                      .toList();
                  if (entries.isEmpty) {
                    return Center(child: Text(translate('No remote history')));
                  }
                  return ListView.separated(
                    itemCount: entries.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final entry = entries[index];
                      final name = _name(entry.id);
                      return ListTile(
                        leading: const Icon(Icons.history),
                        title: SelectableText(
                            name.isEmpty ? entry.id : '$name (${entry.id})'),
                        subtitle: Text(formatRemoteHistoryTime(entry.time)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('Close')),
        ),
      ],
    );
  }
}

String formatRemoteHistoryTime(int milliseconds) {
  final time = DateTime.fromMillisecondsSinceEpoch(milliseconds);
  String twoDigits(int value) => value.toString().padLeft(2, '0');
  return '${twoDigits(time.day)}/${twoDigits(time.month)}/${time.year.toString().padLeft(4, '0')} '
      '${twoDigits(time.hour)}:${twoDigits(time.minute)}:${twoDigits(time.second)}';
}

Widget remoteHistoryTime(Peer peer) {
  final time = formatRemoteHistoryTime(peer.remoteHistory.first);
  return Tooltip(
    message: '${translate('Last remote session')}: $time',
    child: Row(
      children: [
        const Icon(Icons.access_time, size: 12),
        const SizedBox(width: 4),
        Expanded(
          child: Text(time,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11)),
        ),
      ],
    ),
  );
}

void showRemoteHistory(BuildContext context, Peer peer) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('${translate('Remote history')} — ${peer.getId()}'),
      content: SizedBox(
        width: 420,
        height: 360,
        child: ListView.builder(
          itemCount: peer.remoteHistory.length,
          itemBuilder: (context, index) => ListTile(
            leading: const Icon(Icons.access_time),
            title: SelectableText(
                formatRemoteHistoryTime(peer.remoteHistory[index])),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(translate('Close')),
        ),
      ],
    ),
  );
}
