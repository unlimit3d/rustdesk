import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../common.dart';
import '../../models/platform_model.dart';

class CrhUpdateButton extends StatefulWidget {
  const CrhUpdateButton({Key? key}) : super(key: key);

  @override
  State<CrhUpdateButton> createState() => _CrhUpdateButtonState();
}

class _CrhUpdateButtonState extends State<CrhUpdateButton> {
  bool _checking = false;
  String? _error;
  Map<String, dynamic>? _release;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _check(manual: false);
    });
  }

  Future<void> _check({required bool manual}) async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _error = null;
    });
    try {
      final response =
          jsonDecode(await bind.mainGetCommon(key: 'crhrustdesk-check-update'))
              as Map<String, dynamic>;
      if (response['error'] != null) {
        throw StateError(response['error'].toString());
      }
      if (!mounted) return;
      if (response['supported'] != true) {
        throw UnsupportedError(
            translate('Supported only in the installed version.'));
      }
      setState(
          () => _release = response['available'] == true ? response : null);
      if (_release != null || manual) await _showResult();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _release = null;
        _error = error.toString();
      });
      if (manual) await _showResult();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showResult() async {
    final release = _release;
    final download = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(translate(_error != null
            ? 'Update check failed'
            : release == null
                ? 'Up to date'
                : 'Update available')),
        content: _error != null
            ? SelectableText(_error!)
            : release == null
                ? null
                : Text('${release['version']} · ${release['revision']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(translate('Close')),
          ),
          if (release != null)
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(translate('Download new version')),
            ),
        ],
      ),
    );
    if (download == true && release != null) {
      try {
        final opened = await launchUrlString(release['url'] as String,
            mode: LaunchMode.externalApplication);
        if (!opened) throw StateError('Could not open the verified update URL');
      } catch (error) {
        if (mounted) setState(() => _error = error.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: _checking ? null : () => _check(manual: true),
            icon: _checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.system_update_alt, size: 18),
            label: Text(translate('Check for updates')),
          ),
          if (_release != null)
            TextButton(
              onPressed: _checking ? null : _showResult,
              child: Text(translate('Update available')),
            ),
          if (_error != null)
            Text(translate('Update check failed'),
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
    );
  }
}
