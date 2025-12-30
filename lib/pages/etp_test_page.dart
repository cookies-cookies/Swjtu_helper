import 'package:flutter/material.dart';
import '../services/etp_service.dart';
import '../services/etp_login_service.dart';
import '../services/credential_storage_service.dart';
import '../services/jsessionid_service.dart';

/// 实验教学平台测试页面
class EtpTestPage extends StatefulWidget {
  final JSessionIdService service;

  const EtpTestPage({super.key, required this.service});

  @override
  State<EtpTestPage> createState() => _EtpTestPageState();
}

class _EtpTestPageState extends State<EtpTestPage> {
  final EtpService _etpService = EtpService();
  final EtpLoginService _loginService = EtpLoginService();
  final CredentialStorageService _credentialStorage =
      CredentialStorageService();
  final TextEditingController _ytokenController = TextEditingController();
  final TextEditingController _xqmController = TextEditingController(
    text: '120',
  );
  bool _isLoading = false;
  final List<String> _logs = [];
  List<Map<String, dynamic>> _courseList = [];
  int _totalCourses = 0;

  @override
  void initState() {
    super.initState();
    _loadYtoken();
  }

  /// 自动加载保存的 Ytoken
  Future<void> _loadYtoken() async {
    final ytoken = await _credentialStorage.loadYtoken();
    if (ytoken != null) {
      setState(() {
        _ytokenController.text = ytoken;
      });
      _addLog('✅ 已加载缓存的 Ytoken');
    } else {
      _addLog('⚠️ 未找到缓存的 Ytoken，请先在主页登录');
    }
  }

  void _addLog(String log) {
    setState(() {
      _logs.add('[${DateTime.now().toString().substring(11, 19)}] $log');
      if (_logs.length > 100) _logs.removeAt(0);
    });
  }

  /// 测试获取实验选课列表（获取所有页）
  Future<void> _testCourseList() async {
    if (_ytokenController.text.isEmpty) {
      _addLog('错误: 请先输入 Ytoken');
      return;
    }

    setState(() {
      _isLoading = true;
      _courseList = [];
      _totalCourses = 0;
    });
    _etpService.setYtoken(_ytokenController.text);

    _addLog('开始获取所有实验选课数据...');

    final pages = await _etpService.getAllExperimentCoursePages(
      xqm: _xqmController.text,
      pageSize: 20,
    );

    final logs = _etpService.takeLogs();
    for (final log in logs) {
      _addLog(log);
    }

    if (pages.isNotEmpty) {
      // 合并所有页的数据
      final allData = <Map<String, dynamic>>[];
      for (final page in pages) {
        allData.addAll(
          page.map((item) => Map<String, dynamic>.from(item as Map)),
        );
      }

      setState(() {
        _courseList = allData;
        _totalCourses = _courseList.length;
      });
      _addLog('✅ 成功获取所有数据，共 ${pages.length} 页，$_totalCourses 条记录');
    } else {
      _addLog('❌ 获取失败');
    }

    setState(() => _isLoading = false);
  }

  /// 测试获取实验成绩
  Future<void> _testScoreList() async {
    if (_ytokenController.text.isEmpty) {
      _addLog('错误: 请先从主页登录获取 Ytoken');
      return;
    }

    setState(() => _isLoading = true);
    _etpService.setYtoken(_ytokenController.text);

    _addLog('开始获取实验成绩数据...');

    final result = await _etpService.getExperimentScoreList(
      xqm: _xqmController.text,
      pageNum: 1,
      pageSize: 20,
    );

    final logs = _etpService.takeLogs();
    for (final log in logs) {
      _addLog(log);
    }

    if (result != null && result['status'] == true) {
      final total = result['total'] ?? 0;
      final dataList = result['data'] as List?;
      _addLog('✅ 成功获取实验成绩');
      _addLog('   总记录数: $total');
      if (dataList != null && dataList.isNotEmpty) {
        _addLog('   当前页记录: ${dataList.length} 条');
        _addLog('数据已保存到 debug_etp_score_list_page1.json');
      }
    } else {
      _addLog('❌ 获取失败');
    }

    setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('实验教学平台测试'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Ytoken 输入
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'JWT Token (Ytoken)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _ytokenController,
                      decoration: InputDecoration(
                        hintText: '从主页登录后自动加载...',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh),
                          onPressed: _loadYtoken,
                          tooltip: '重新加载',
                        ),
                      ),
                      readOnly: true,
                      maxLines: 3,
                      style: const TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '学期码 (xqm)',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _xqmController,
                      decoration: const InputDecoration(
                        hintText: '例如: 120',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 测试按钮
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '测试功能',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _testCourseList,
                          icon: const Icon(Icons.list, size: 18),
                          label: const Text('获取选课列表'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isLoading ? null : _testScoreList,
                          icon: const Icon(Icons.grade, size: 18),
                          label: const Text('获取实验成绩'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () {
                            setState(() => _logs.clear());
                          },
                          icon: const Icon(Icons.clear_all, size: 18),
                          label: const Text('清空日志'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 课程列表展示
            if (_courseList.isNotEmpty)
              Expanded(
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.school, size: 18),
                            const SizedBox(width: 8),
                            Text(
                              '实验选课结果（共 $_totalCourses 条）',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(6),
                          itemCount: _courseList.length,
                          itemBuilder: (context, index) {
                            final course = _courseList[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 6),
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      course['kcmc'] ?? '未知课程',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _buildInfoRow('实验项目', course['syxmmc']),
                                    _buildInfoRow('开课单位', course['dwmc']),
                                    _buildInfoRow('实验室', course['sysmc']),
                                    _buildInfoRow(
                                      '地点',
                                      course['fwmc'] ?? course['fwtybh'],
                                    ),
                                    _buildInfoRow('指导教师', course['syzdjsxm']),
                                    _buildInfoRow(
                                      '学时',
                                      course['syxmxs']?.toString(),
                                    ),
                                    if (course['syxmrq'] != null)
                                      _buildInfoRow('时间', course['syxmrq']),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 日志区域
            if (_courseList.isEmpty)
              Expanded(
                child: Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(4),
                            topRight: Radius.circular(4),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.terminal, size: 18),
                            const SizedBox(width: 8),
                            const Text(
                              '操作日志',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_isLoading)
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _logs.isEmpty
                            ? const Center(
                                child: Text(
                                  '暂无日志',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              )
                            : Container(
                                color: Colors.grey[50],
                                child: ListView.builder(
                                  padding: const EdgeInsets.all(8),
                                  itemCount: _logs.length,
                                  itemBuilder: (context, index) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 2,
                                      ),
                                      child: Text(
                                        _logs[index],
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontFamily: 'monospace',
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String? value) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 65,
            child: Text(
              '$label:',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _etpService.dispose();
    _loginService.dispose();
    _ytokenController.dispose();
    _xqmController.dispose();
    super.dispose();
  }
}
