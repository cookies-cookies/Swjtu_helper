import 'package:flutter/material.dart';
import '../models/experiment_score.dart';
import '../services/etp_service.dart';
import '../services/credential_storage_service.dart';

class ExperimentScoresPage extends StatefulWidget {
  const ExperimentScoresPage({super.key});

  @override
  State<ExperimentScoresPage> createState() => _ExperimentScoresPageState();
}

class _ExperimentScoresPageState extends State<ExperimentScoresPage> {
  final EtpService _etpService = EtpService();
  final CredentialStorageService _credentialStorage =
      CredentialStorageService();

  List<ExperimentScore> _scores = [];
  bool _loading = false;
  String? _error;
  String _xqm = '120';

  @override
  void initState() {
    super.initState();
    _loadScores();
  }

  Future<void> _loadScores() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 加载 Ytoken
      final ytoken = await _credentialStorage.loadYtoken();

      if (ytoken == null || ytoken.isEmpty) {
        setState(() {
          _error = '未找到 Ytoken\n\n请先在主页登录获取认证令牌';
          _loading = false;
        });
        return;
      }

      _etpService.setYtoken(ytoken);

      // 获取实验成绩数据（JSON格式）
      final result = await _etpService.getExperimentScoreList(
        xqm: _xqm,
        pageNum: 1,
        pageSize: 100, // 一次获取更多数据
      );

      if (result == null ||
          (result['code'] != '00000' && result['status'] != true)) {
        setState(() {
          _error = '获取实验成绩失败\n\n请检查网络连接或重新登录';
          _loading = false;
        });
        return;
      }

      final dataList = result['data'] as List?;

      if (dataList == null || dataList.isEmpty) {
        setState(() {
          _error = '暂无实验成绩数据';
          _loading = false;
        });
        return;
      }

      // 解析数据
      final scores = <ExperimentScore>[];
      for (var i = 0; i < dataList.length; i++) {
        final item = dataList[i] as Map<String, dynamic>;

        // 成绩字段: syxmcj
        final scoreValue = item['syxmcj'];
        String? scoreStr;
        if (scoreValue != null) {
          scoreStr = scoreValue.toString();
        }

        // 评价状态: pjzt (0=未评价, 1=已评价)
        final pjzt = item['pjzt'] as int?;
        final cjtjzt = item['cjtjzt'] as int?; // 成绩提交状态 (0=未提交, 1=已提交)

        // 评价分数: pjfs
        final pjfsValue = item['pjfs'];
        double? evaluationScore;
        if (pjfsValue != null) {
          evaluationScore = (pjfsValue is num)
              ? pjfsValue.toDouble()
              : double.tryParse(pjfsValue.toString());
        }

        // 可评价条件：cjtjzt=1(教师已提交成绩) AND pjzt=0(学生未评价)
        // 无论成绩是否为null，只要教师提交了就可以评价
        final needsEval = cjtjzt == 1 && pjzt == 0;

        // 实验时间
        String? expTime;
        if (item['kssj'] != null) {
          expTime = item['kssj'].toString();
        } else if (item['zc'] != null && item['xq'] != null) {
          expTime = '第${item['zc']}周 周${item['xq']}';
        }

        scores.add(
          ExperimentScore(
            id: item['sid']?.toString() ?? 'exp_$i',
            courseName: item['kcmc']?.toString() ?? '未知课程',
            experimentName: item['syxmmc']?.toString() ?? '未知实验',
            teacher: item['zdjsxm']?.toString() ?? '',
            score: scoreStr,
            needsEvaluation: needsEval,
            evaluationStatus: pjzt == 1 ? '已评价' : (needsEval ? '待评价' : '未提交'),
            submitDate: item['pjsj']?.toString(),
            experimentDate: expTime,
            evaluationScore: evaluationScore,
          ),
        );
      }

      setState(() {
        _scores = scores;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  /// 一键自动评价所有待评价实验
  Future<void> _autoEvaluateAll() async {
    final needEvalList = _scores.where((s) => s.needsEvaluation).toList();

    if (needEvalList.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('没有需要评价的实验')));
      }
      return;
    }

    // 确认对话框
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认一键评价'),
        content: Text('将自动评价 ${needEvalList.length} 个实验项目\n\n评价内容：满分好评'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('开始评价'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _loading = true);

    try {
      // 先获取评价模板
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('正在获取评价模板...')));
      }

      // 第一步: 获取模板ID
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('正在获取评价模板...')));
      }

      final mbh = await _etpService.getEvaluateTemplateId();

      if (mbh == null) {
        throw Exception('获取评价模板ID失败');
      }

      // 第二步: 获取完整模板
      final template = await _etpService.getEvaluateTemplate(mbh);

      if (template == null) {
        throw Exception('获取完整评价模板失败');
      }

      // 解析题目列表
      final titles =
          (template['data']['titles'] as List?)?.cast<Map<String, dynamic>>() ??
          [];

      if (titles.isEmpty) {
        throw Exception('评价模板没有题目');
      }

      // 第三步: 逐个提交评价
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('开始批量评价 ${needEvalList.length} 个实验...')),
        );
      }

      int successCount = 0;
      int failCount = 0;
      final errors = <String>[];

      for (int i = 0; i < needEvalList.length; i++) {
        final experiment = needEvalList[i];

        try {
          final result = await _etpService.submitEvaluation(
            experimentId: experiment.id,
            template: template,
          );

          if (result != null && result['code'] == '00000') {
            successCount++;
            print('[评价] ✅ ${experiment.experimentName} - 成功');
          } else {
            failCount++;
            final error =
                '${experiment.experimentName}: ${result?['message'] ?? '未知错误'}';
            errors.add(error);
            print('[评价] ❌ $error');
          }
        } catch (e) {
          failCount++;
          final error = '${experiment.experimentName}: $e';
          errors.add(error);
          print('[评价] ❌ $error');
        }

        // 短暂延迟,避免请求过快
        if (i < needEvalList.length - 1) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      // 显示结果
      if (mounted) {
        final resultMessage = StringBuffer();
        resultMessage.writeln('✅ 批量评价完成！');
        resultMessage.writeln('');
        resultMessage.writeln('成功: $successCount 个');
        if (failCount > 0) {
          resultMessage.writeln('失败: $failCount 个');
          resultMessage.writeln('');
          resultMessage.writeln('失败原因:');
          for (final error in errors) {
            resultMessage.writeln('• $error');
          }
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(resultMessage.toString()),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(label: '刷新', onPressed: _loadScores),
          ),
        );

        // 自动刷新列表
        if (successCount > 0) {
          await Future.delayed(const Duration(seconds: 1));
          _loadScores();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('评价失败: $e')));
      }
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 统计待评价数量
    final needEvalCount = _scores.where((s) => s.needsEvaluation).length;

    return Scaffold(
      appBar: AppBar(
        title: Text('实验成绩${needEvalCount > 0 ? ' ($needEvalCount 个待评价)' : ''}'),
        actions: [
          if (needEvalCount > 0)
            TextButton.icon(
              onPressed: _loading ? null : _autoEvaluateAll,
              icon: const Icon(Icons.auto_awesome, color: Colors.white),
              label: const Text('一键评价', style: TextStyle(color: Colors.white)),
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loading ? null : _loadScores,
            tooltip: '刷新',
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载实验成绩...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadScores,
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_scores.isEmpty) {
      return const Center(child: Text('暂无实验成绩'));
    }

    return _buildScoresList();
  }

  Widget _buildScoresList() {
    // 按课程分组
    final Map<String, List<ExperimentScore>> groupedScores = {};
    for (var score in _scores) {
      groupedScores.putIfAbsent(score.courseName, () => []).add(score);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: groupedScores.length,
      itemBuilder: (context, index) {
        final courseName = groupedScores.keys.elementAt(index);
        final courseScores = groupedScores[courseName]!;

        return _buildCourseCard(courseName, courseScores);
      },
    );
  }

  Widget _buildCourseCard(String courseName, List<ExperimentScore> scores) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text(
          courseName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        subtitle: Text('${scores.length} 个实验'),
        children: scores.map((score) => _buildScoreItem(score)).toList(),
      ),
    );
  }

  Widget _buildScoreItem(ExperimentScore score) {
    Color statusColor;
    IconData statusIcon;

    if (score.evaluationScore != null && score.evaluationScore! > 0) {
      // 已评价（有评价分数）
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (score.needsEvaluation) {
      // 待评价（cjtjzt=1 且 pjzt=0）
      statusColor = Colors.orange;
      statusIcon = Icons.rate_review;
    } else if (score.hasScore) {
      // 有成绩但不可评价
      statusColor = Colors.blue;
      statusIcon = Icons.grade;
    } else {
      // 无成绩
      statusColor = Colors.grey;
      statusIcon = Icons.hourglass_empty;
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: statusColor.withOpacity(0.1),
        child: Icon(statusIcon, color: statusColor, size: 20),
      ),
      title: Text(score.experimentName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (score.teacher.isNotEmpty)
            Text('教师: ${score.teacher}', style: const TextStyle(fontSize: 12)),
          if (score.experimentDate != null)
            Text(
              '实验日期: ${score.experimentDate}',
              style: const TextStyle(fontSize: 12),
            ),
          // 显示评价状态和分数
          if (score.evaluationScore != null && score.evaluationScore! > 0)
            Text(
              '评价: ${score.evaluationScore!.toStringAsFixed(1)}分 (已评价)',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.green,
                fontWeight: FontWeight.bold,
              ),
            )
          else if (score.needsEvaluation)
            Text(
              score.hasScore ? '待评价 (可查看成绩: ${score.score})' : '待评价 (评价后可查看成绩)',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            )
          else if (!score.hasScore)
            const Text(
              '教师未提交成绩',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
        ],
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            score.scoreDisplay,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: score.hasScore ? Colors.green : statusColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            score.statusDisplay,
            style: TextStyle(fontSize: 12, color: statusColor),
          ),
        ],
      ),
      onTap: score.needsEvaluation
          ? () {
              // TODO: 实现评价功能
              _showEvaluationDialog(score);
            }
          : null,
    );
  }

  void _showEvaluationDialog(ExperimentScore score) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('实验评价'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('课程: ${score.courseName}'),
            Text('实验: ${score.experimentName}'),
            const SizedBox(height: 16),
            const Text(
              '评价功能需要根据实际页面实现，\n请在浏览器中完成评价。',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _loadScores(); // 刷新数据
            },
            child: const Text('刷新'),
          ),
        ],
      ),
    );
  }
}
