import 'package:flutter_hbb/common/widgets/remote_history.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shows the local connection date and time including seconds', () {
    final time = DateTime(2026, 11, 17, 9, 5, 3);
    expect(formatRemoteHistoryTime(time.millisecondsSinceEpoch),
        '17/11/2026 09:05:03');
  });

  test('recent peers keep every recorded connection when copied', () {
    final peer = Peer.fromJson({
      'id': '172.29.0.52',
      'remote_history': '[3000,3000,1000]',
    });
    expect(Peer.copy(peer).remoteHistory, [3000, 3000, 1000]);
    expect(Peer.fromJson({'id': 'old-peer'}).remoteHistory, isEmpty);
  });

  test('combined report retains every session and lists newest first', () {
    final history = decodeRemoteHistory(
        '{"history":{"172.29.0.52":[3000,1000],"262799361":[2000]}}');
    expect(history.map((entry) => entry.id),
        ['172.29.0.52', '262799361', '172.29.0.52']);
    expect(history.map((entry) => entry.time), [3000, 2000, 1000]);
    expect(decodeRemoteHistory('{"history":{}}'), isEmpty);
  });
}
