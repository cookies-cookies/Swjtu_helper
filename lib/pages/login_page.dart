import 'package:flutter/material.dart';
import '../services/cas_login_service.dart';

/// 登录页面
class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _casService = CasLoginService();

  bool _isLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _checkExistingLogin();
  }

  /// 检查是否已有登录状态
  Future<void> _checkExistingLogin() async {
    setState(() => _isLoading = true);

    final hasLoadedCookies = await _casService.loadCookies();
    if (hasLoadedCookies) {
      final isLoggedIn = await _casService.isLoggedIn();
      if (isLoggedIn) {
        if (mounted) {
          _showMessage('检测到已登录状态', isError: false);
          _navigateToHome();
        }
      }
    }

    setState(() => _isLoading = false);
  }

  /// 执行登录
  Future<void> _performLogin() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    final result = await _casService.login(username, password);

    setState(() => _isLoading = false);

    if (mounted) {
      _showMessage(result.message, isError: !result.success);

      if (result.success) {
        _navigateToHome();
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

  /// 导航到主页
  void _navigateToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => HomePage(casService: _casService),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('西南交大 CAS 登录'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Logo/图标
                    Icon(
                      Icons.school,
                      size: 80,
                      color: Theme.of(context).primaryColor,
                    ),
                    const SizedBox(height: 24),

                    // 标题
                    Text(
                      '教务处登录系统',
                      style: Theme.of(context).textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),

                    // 用户名输入框
                    TextFormField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: '学号',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return '请输入学号';
                        }
                        return null;
                      },
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 16),

                    // 密码输入框
                    TextFormField(
                      controller: _passwordController,
                      decoration: InputDecoration(
                        labelText: '密码',
                        prefixIcon: const Icon(Icons.lock),
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () {
                            setState(() {
                              _obscurePassword = !_obscurePassword;
                            });
                          },
                        ),
                      ),
                      obscureText: _obscurePassword,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return '请输入密码';
                        }
                        return null;
                      },
                      enabled: !_isLoading,
                    ),
                    const SizedBox(height: 24),

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
                          : const Text('登录', style: TextStyle(fontSize: 16)),
                    ),

                    const SizedBox(height: 16),

                    // 提示信息
                    Text(
                      '提示:使用统一身份认证账号登录',
                      style: Theme.of(context).textTheme.bodySmall,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 主页 - 登录后的页面
class HomePage extends StatefulWidget {
  final CasLoginService casService;

  const HomePage({super.key, required this.casService});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _userFrameworkContent;
  bool _isLoading = false;
  final List<String> _logs = [];

  @override
  void initState() {
    super.initState();
    // 初始不自动登录，等待用户按下 login 按钮（与 Python 交互类似）
  }

  void _appendLog(String line) {
    setState(() {
      final ts = DateTime.now().toIso8601String();
      _logs.add('[$ts] $line');
      if (_logs.length > 500) _logs.removeAt(0);
    });
  }

  void _drainServiceLogs() {
    final lines = widget.casService.takeLogs();
    if (lines.isEmpty) return;
    setState(() {
      final ts = DateTime.now().toIso8601String();
      for (final l in lines) {
        _logs.add('[$ts] $l');
      }
      while (_logs.length > 500) _logs.removeAt(0);
    });
  }

  /// 加载 UserFramework
  Future<void> _loadUserFramework() async {
    setState(() => _isLoading = true);
    final content = await widget.casService.getUserFramework();
    _drainServiceLogs();
    if (mounted) {
      setState(() {
        _userFrameworkContent = content;
        _isLoading = false;
      });
      if (content != null) {
        _appendLog('UserFramework length=${content.length}');
      } else {
        _appendLog('UserFramework fetch failed');
      }
    }
  }

  /// 加载学生信息
  Future<void> _loadStudentInfo() async {
    setState(() => _isLoading = true);
    final content = await widget.casService.getStudentInfo();
    _drainServiceLogs();
    if (mounted) {
      setState(() => _isLoading = false);
      if (content != null) {
        _showDialog('学生信息', content);
        _appendLog('StudentInfo length=${content.length}');
      } else {
        _showMessage('获取学生信息失败');
        _appendLog('StudentInfo fetch failed');
      }
    }
  }

  Future<void> _status() async {
    final s = await widget.casService.isLoggedIn();
    _drainServiceLogs();
    _appendLog('status: logged=$s');
    _showMessage(s ? '已登录' : '未登录');
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);
    final r = await widget.casService.login('ignored', 'ignored');
    _drainServiceLogs();
    setState(() => _isLoading = false);
    _appendLog('login result: ${r.success}');
    _showMessage(r.message);
  }

  /// 退出登录
  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认退出'),
        content: const Text('确定要退出登录吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.casService.logout();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (context) => const LoginPage()),
        );
      }
    }
  }

  /// 显示对话框
  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: SelectableText(
            content.length > 1000
                ? '${content.substring(0, 1000)}...'
                : content,
            style: const TextStyle(fontSize: 12),
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

  /// 显示消息
  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('教务处系统'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: '退出登录',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ElevatedButton.icon(
                      onPressed: _status,
                      icon: const Icon(Icons.info_outline),
                      label: const Text('status'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _loadUserFramework,
                      icon: const Icon(Icons.dashboard),
                      label: const Text('userframework'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _loadStudentInfo,
                      icon: const Icon(Icons.person),
                      label: const Text('studentinfo'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _login,
                      icon: const Icon(Icons.login),
                      label: const Text('login'),
                    ),
                    ElevatedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.exit_to_app),
                      label: const Text('exit'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        _drainServiceLogs();
                        _appendLog('flush logs');
                      },
                      icon: const Icon(Icons.sync),
                      label: const Text('flush'),
                    ),
                    ElevatedButton.icon(
                      onPressed: () {
                        final cookies = widget.casService.getCookies();
                        if (cookies.isEmpty) {
                          _appendLog('cookies: (empty)');
                        } else {
                          cookies.forEach((k,v){
                            _appendLog('cookie $k=${v.length>60? v.substring(0,60)+"...":v}');
                          });
                        }
                      },
                      icon: const Icon(Icons.cookie),
                      label: const Text('cookies'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.dashboard, color: Colors.blue),
                    title: const Text('UserFramework 内容'),
                    subtitle: Text(_userFrameworkContent == null
                        ? '未加载'
                        : '长度 ${_userFrameworkContent!.length}'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      if (_userFrameworkContent != null) {
                        _showDialog('UserFramework', _userFrameworkContent!);
                      } else {
                        _showMessage('内容为空');
                      }
                    },
                  ),
                ),
                const SizedBox(height: 24),
                Text('日志输出 (最多500条)', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Container(
                  constraints: const BoxConstraints(minHeight: 160, maxHeight: 300),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.black26),
                  ),
                  child: _logs.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(8.0),
                          child: Text('暂无日志', style: TextStyle(fontSize: 12, color: Colors.grey)),
                        )
                      : ListView.builder(
                          itemCount: _logs.length,
                          itemBuilder: (c, i) => Text(
                            _logs[i],
                            style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                          ),
                        ),
                ),
                const SizedBox(height: 24),
                const Divider(),
                const Text(
                  '命令说明: status / userframework / studentinfo / login / exit / flush\n'
                  '流程与 Python 脚本一致, 登录凭据已硬编码在服务中。若出现 captcha/slider 需求将失败。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    widget.casService.dispose();
    super.dispose();
  }
}
