import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../constants.dart';
import '../theme/app_theme.dart';

class GitHubAuthScreen extends StatefulWidget {
  final String jwtToken;
  const GitHubAuthScreen({Key? key, required this.jwtToken}) : super(key: key);

  @override
  State<GitHubAuthScreen> createState() => _GitHubAuthScreenState();
}

class _GitHubAuthScreenState extends State<GitHubAuthScreen> {
  late final WebViewController _controller;
  final loginUrl = Uri.parse('${kServerIp}/auth/github/login?token=');

  @override
  void initState() {
    super.initState();

    final url = Uri.parse(
      '${kServerIp}/auth/github/login?token=${widget.jwtToken}',
    );

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      // Открытие во внешнем браузере на десктопе
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
        // Закрываем экран после открытия ссылки  
        Navigator.of(context).pop();
      });
    } else {
      // Настройка WebView для Android/iOS
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onNavigationRequest: (request) {
              final url = request.url;
              if (url.startsWith('androidide://auth/success')) {
                final token = Uri.parse(url).queryParameters['token'];
                Navigator.of(context).pop(token);
                return NavigationDecision.prevent;
              }
              return NavigationDecision.navigate;
            },
            onWebResourceError: (error) {
              // можно добавить обработку ошибок
            },
          ),
        )
        ..loadRequest(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    // На Windows/LINUX/macOS — отображаем загрузку (экран закроется автоматически)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return Scaffold(
        backgroundColor: AppTheme.getBg(context),
        body: Center(
          child: CircularProgressIndicator(
            color: AppTheme.getAccent(context),
          ),
        ),
      );
    }

    // На Android/iOS — отображаем WebView
    return Scaffold(
      backgroundColor: AppTheme.getBg(context),
      appBar: AppBar(
        backgroundColor: AppTheme.getRailBg(context),
        title: Text(
          'GitHub Login',
          style: TextStyle(color: AppTheme.getTextColor(context)),
        ),
        iconTheme: IconThemeData(color: AppTheme.getTextColor(context)),
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}