import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/jsessionid_service.dart';
import '../services/dio_cas_login_service.dart';
import '../services/etp_login_service.dart';
import '../services/credential_storage_service.dart';
import 'home_page.dart';

/// JSESSIONID 登录页面
class JSessionIdLoginPage extends StatefulWidget {
  const JSessionIdLoginPage({super.key});

  @override
  State<JSessionIdLoginPage> createState() => _JSessionIdLoginPageState();
}

class _JSessionIdLoginPageState extends State<JSessionIdLoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _jsessionidController = TextEditingController();
  final _ytokenController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _jsessionidService = JSessionIdService();
  final _credentialStorage = CredentialStorageService();

  bool _isLoading = false;
  bool _obscureText = true;
  bool _obscureYtoken = true;
  DioCasLoginService? _dioService;
  EtpLoginService? _etpService;

  @override
  void initState() {
    super.initState();
    _autoLoginWithCache();
  }

  /// 自动登录：优先使用缓存的 JSESSIONID 和 Ytoken，失败后使用账号密码
  Future<void> _autoLoginWithCache() async {
    // 1. 先尝试使用缓存的 JSESSIONID
    final cachedJsessionId = await _credentialStorage.loadJSessionId();
    if (cachedJsessionId != null) {
      _jsessionidController.text = cachedJsessionId;
      _showMessage('✓ 发现缓存的 JSESSIONID', isError: false);
    }

    // 2. 尝试使用缓存的 Ytoken
    final cachedYtoken = await _credentialStorage.loadYtoken();
    if (cachedYtoken != null) {
      _ytokenController.text = cachedYtoken;
      _showMessage('✓ 发现缓存的 Ytoken', isError: false);
    }

    // 3. 加载保存的账号密码（如果有）
    final credentials = await _credentialStorage.loadCredentials();
    if (credentials != null) {
      _usernameController.text = credentials['username']!;
      _passwordController.text = credentials['password']!;
      if (cachedJsessionId == null || cachedYtoken == null) {
        _showMessage('✓ 发现保存的账号，可点击"CAS自动登录"', isError: false);
      }
    }
  }

  @override
  void dispose() {
    _jsessionidController.dispose();
    _ytokenController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _dioService?.dispose();
    _etpService?.dispose();
    super.dispose();
  }

  /// Dio 自动登录（同时获取 JSESSIONID 和 Ytoken）
  Future<void> _dioAutoLogin() async {
    // 弹出对话框让用户输入用户名和密码（预填充保存的账号）
    final credentials = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _CredentialsDialog(
        initialUsername: _usernameController.text,
        initialPassword: _passwordController.text,
        title: 'CAS 统一认证登录',
      ),
    );

    if (credentials == null) return;

    final username = credentials['username']!;
    final password = credentials['password']!;
    final rememberMe = credentials['rememberMe'] == 'true';

    setState(() => _isLoading = true);

    try {
      _dioService = DioCasLoginService();
      final result = await _dioService!.login(username, password);

      setState(() => _isLoading = false);

      if (mounted) {
        if (result.success && result.jsessionId != null) {
          _jsessionidController.text = result.jsessionId!;

          // 同时获取 ETP 的 Ytoken
          _showMessage('正在获取 ETP Ytoken...', isError: false);
          _etpService = EtpLoginService();
          final etpResult = await _etpService!.login(username, password);

          if (etpResult.success && etpResult.ytoken != null) {
            _ytokenController.text = etpResult.ytoken!;
            await _credentialStorage.saveYtoken(etpResult.ytoken!);
            _showMessage('✓ Ytoken 已获取并保存', isError: false);
          }

          // 保存凭证
          if (rememberMe) {
            await _credentialStorage.saveCredentials(username, password);
            await _credentialStorage.saveJSessionId(result.jsessionId!);
            _showMessage('✓ ${result.message}（已保存账号和会话）', isError: false);
          } else {
            await _credentialStorage.clearCredentials();
            await _credentialStorage.saveJSessionId(result.jsessionId!);
            _showMessage('✓ ${result.message}', isError: false);
          }

          // 显示日志
          _showDioLogs(_dioService!.logs);
        } else {
          _showMessage('✗ ${result.message}', isError: true);
          // 即使失败也显示日志
          _showDioLogs(_dioService!.logs);
        }
      }
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        _showMessage('异常: $e', isError: true);
      }
    }
  }

  /// 显示 Dio 登录日志
  void _showDioLogs(List<String> logs) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('登录日志'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: ListView.builder(
            itemCount: logs.length,
            itemBuilder: (context, index) {
              final log = logs[index];
              final isError = log.contains('✗') || log.contains('!');
              final isSuccess = log.contains('✓') || log.contains('成功');

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  log,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: isError
                        ? Colors.red
                        : (isSuccess ? Colors.green : Colors.black87),
                  ),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 执行登录验证
  Future<void> _performLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final jsessionid = _jsessionidController.text.trim();

    setState(() => _isLoading = true);

    final result = await _jsessionidService.loginWithJSessionId(jsessionid);

    setState(() => _isLoading = false);

    if (mounted) {
      if (result.success) {
        _showMessage('登录成功！', isError: false);
        // 导航到功能页面
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => HomePage(service: _jsessionidService),
          ),
        );
      } else {
        _showMessage(result.message, isError: true);
      }
    }
  }

  /// 显示消息
  void _showMessage(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教务处登录系统'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Logo/图标
                      Icon(
                        Icons.lock_person,
                        size: 80,
                        color: Theme.of(context).primaryColor,
                      ),
                      const SizedBox(height: 24),

                      // 标题
                      Text(
                        'JSESSIONID 登录',
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),

                      // 副标题
                      Text(
                        '请输入浏览器中的 JSESSIONID',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[600],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),

                      // JSESSIONID 输入框
                      TextFormField(
                        controller: _jsessionidController,
                        decoration: InputDecoration(
                          labelText: 'JSESSIONID',
                          prefixIcon: const Icon(Icons.vpn_key),
                          border: const OutlineInputBorder(),
                          helperText: '从浏览器开发者工具中获取',
                          helperMaxLines: 2,
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _obscureText
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureText = !_obscureText;
                                  });
                                },
                                tooltip: _obscureText ? '显示' : '隐藏',
                              ),
                              IconButton(
                                icon: const Icon(Icons.paste),
                                onPressed: () async {
                                  final data = await Clipboard.getData(
                                    'text/plain',
                                  );
                                  if (data?.text != null) {
                                    _jsessionidController.text = data!.text!
                                        .trim();
                                    if (mounted) {
                                      _showMessage('已粘贴', isError: false);
                                    }
                                  }
                                },
                                tooltip: '粘贴',
                              ),
                            ],
                          ),
                        ),
                        obscureText: _obscureText,
                        maxLines: 1,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return '请输入 JSESSIONID';
                          }
                          if (value.trim().length < 10) {
                            return 'JSESSIONID 长度不正确';
                          }
                          return null;
                        },
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 16),

                      // Ytoken 输入框
                      TextFormField(
                        controller: _ytokenController,
                        decoration: InputDecoration(
                          labelText: 'Ytoken（ETP 实验教学平台）',
                          prefixIcon: const Icon(Icons.science),
                          border: const OutlineInputBorder(),
                          helperText: 'ETP 平台的认证令牌',
                          helperMaxLines: 2,
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(
                                  _obscureYtoken
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureYtoken = !_obscureYtoken;
                                  });
                                },
                                tooltip: _obscureYtoken ? '显示' : '隐藏',
                              ),
                              IconButton(
                                icon: const Icon(Icons.paste),
                                onPressed: () async {
                                  final data = await Clipboard.getData(
                                    'text/plain',
                                  );
                                  if (data?.text != null) {
                                    _ytokenController.text = data!.text!.trim();
                                    if (mounted) {
                                      _showMessage(
                                        '已粘贴 Ytoken',
                                        isError: false,
                                      );
                                    }
                                  }
                                },
                                tooltip: '粘贴',
                              ),
                            ],
                          ),
                        ),
                        obscureText: _obscureYtoken,
                        maxLines: 1,
                      ),
                      const SizedBox(height: 16),

                      // Dio 自动登录按钮（同时获取 JSESSIONID 和 Ytoken）
                      ElevatedButton.icon(
                        onPressed: _isLoading ? null : _dioAutoLogin,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Colors.orange,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.flash_on),
                        label: const Text(
                          'CAS 账号密码自动登录（推荐）',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 32),

                      // 登录按钮
                      ElevatedButton(
                        onPressed: _isLoading ? null : _performLogin,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Text(
                                '验证登录',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),

                      const SizedBox(height: 24),

                      // 帮助信息
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.blue[200]!),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  size: 16,
                                  color: Colors.blue[700],
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '如何获取 JSESSIONID？',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blue[700],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "直接使用CAS登录，等到日志弹出，并且成功获取到就可以了{401是账号密码错误}",
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 凭据输入对话框
class _CredentialsDialog extends StatefulWidget {
  final String? initialUsername;
  final String? initialPassword;
  final String? title;

  const _CredentialsDialog({
    this.initialUsername,
    this.initialPassword,
    this.title,
  });

  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = true;

  @override
  void initState() {
    super.initState();
    _usernameController.text = widget.initialUsername ?? '';
    _passwordController.text = widget.initialPassword ?? '';
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title ?? 'CAS 统一认证登录'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _usernameController,
            decoration: const InputDecoration(
              labelText: '学号',
              prefixIcon: Icon(Icons.person),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: '密码',
              prefixIcon: const Icon(Icons.lock),
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_off : Icons.visibility,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
            ),
          ),
          const SizedBox(height: 16),
          CheckboxListTile(
            title: const Text('记住账号密码'),
            value: _rememberMe,
            onChanged: (value) {
              setState(() {
                _rememberMe = value ?? true;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: () {
            final username = _usernameController.text.trim();
            final password = _passwordController.text;
            if (username.isNotEmpty && password.isNotEmpty) {
              Navigator.pop(context, {
                'username': username,
                'password': password,
                'rememberMe': _rememberMe.toString(),
              });
            }
          },
          child: const Text('登录'),
        ),
      ],
    );
  }
}
