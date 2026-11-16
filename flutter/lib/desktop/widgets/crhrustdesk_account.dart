import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../common.dart';
import '../../common/widgets/login.dart';
import '../../models/platform_model.dart';

class CrhPermissionsLink extends StatelessWidget {
  const CrhPermissionsLink({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: bind.mainGetApiServer(),
      builder: (context, snapshot) {
        final api = Uri.tryParse(snapshot.data ?? '');
        if (api == null || api.host.isEmpty || api.scheme != 'https') {
          return const SizedBox.shrink();
        }
        final uri = Uri(
            scheme: api.scheme,
            host: api.host,
            port: 21120,
            path: '/_permissions/');
        return TextButton.icon(
          onPressed: () async {
            if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
              showToast(translate('Failed'));
            }
          },
          icon: const Icon(Icons.manage_accounts),
          label: Text(uri.toString()),
        );
      },
    );
  }
}

class CrhAccountGate extends StatelessWidget {
  final Widget child;
  const CrhAccountGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Obx(() => gFFI.userModel.isLogin ? child : const _CrhSignInPage());
  }
}

class _CrhSignInPage extends StatefulWidget {
  const _CrhSignInPage();

  @override
  State<_CrhSignInPage> createState() => _CrhSignInPageState();
}

class _CrhSignInPageState extends State<_CrhSignInPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !gFFI.userModel.isLogin) loginDialog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('CrhRustDesk',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            ElevatedButton(
                onPressed: loginDialog, child: Text(translate('Login'))),
            const SizedBox(height: 16),
            const CrhPermissionsLink(),
          ],
        ),
      ),
    );
  }
}
