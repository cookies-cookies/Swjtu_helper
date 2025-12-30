import 'package:flutter/material.dart';
import '../models/student_score.dart';
import '../models/all_scores.dart';
import '../services/jsessionid_service.dart';
import '../services/html_parser_service.dart';

/// 导航项数据类
class NavItem {
  final IconData icon;
  final String title;
  final String description;

  NavItem({required this.icon, required this.title, required this.description});
}

/// 成绩中心 - 带左侧导航栏的布局页面
class ScoreCenterPage extends StatefulWidget {
  final JSessionIdService service;

  const ScoreCenterPage({super.key, required this.service});

  @override
  State<ScoreCenterPage> createState() => _ScoreCenterPageState();
}

class _ScoreCenterPageState extends State<ScoreCenterPage> {
  int _selectedIndex = 0;
  bool _isLoading = false;
  StudentScore? _normalScore; // 平时成绩
  AllScores? _allScores; // 全部成绩
  String? _errorMsg;

  final List<NavItem> _navItems = [
    NavItem(icon: Icons.assessment, title: '平时成绩', description: '查看课程平时表现分数'),
    NavItem(icon: Icons.school, title: '全部成绩', description: '查看所有学期成绩'),
    NavItem(icon: Icons.trending_up, title: '成绩分析', description: '学分绩点统计分析'),
    NavItem(icon: Icons.info_outline, title: '关于', description: '成绩查询系统说明'),
  ];

  @override
  void initState() {
    super.initState();
    // 初始加载平时成绩
    _loadNormalScore();
  }

  Future<void> _loadNormalScore() async {
    if (_normalScore != null) return; // 已加载
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final html = await widget.service.getStudentScore();
      if (html == null) {
        setState(() {
          _errorMsg = '获取平时成绩失败，请检查网络或重新登录';
          _isLoading = false;
        });
        return;
      }

      final score = HtmlParserService.parseStudentScore(html);
      setState(() {
        _normalScore = score;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = '解析平时成绩失败: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadAllScores() async {
    if (_allScores != null) return; // 已加载
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    try {
      final html = await widget.service.getAllScores();
      if (html == null) {
        setState(() {
          _errorMsg = '获取全部成绩失败，请检查网络或重新登录';
          _isLoading = false;
        });
        return;
      }

      final allScores = HtmlParserService.parseAllScores(html);
      if (allScores == null || allScores.scores.isEmpty) {
        setState(() {
          _errorMsg = '解析成绩数据失败或暂无成绩';
          _isLoading = false;
        });
        return;
      }

      setState(() {
        _allScores = allScores;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = '获取全部成绩失败: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('成绩中心'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Row(
        children: [
          // 左侧导航栏
          _buildSidebar(),
          // 右侧内容区
          Expanded(child: _buildContent()),
        ],
      ),
    );
  }

  /// 构建左侧导航栏
  Widget _buildSidebar() {
    return Container(
      width: 240,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        border: Border(right: BorderSide(color: Colors.grey[300]!, width: 1)),
      ),
      child: ListView.builder(
        itemCount: _navItems.length,
        itemBuilder: (context, index) {
          final item = _navItems[index];
          final isSelected = _selectedIndex == index;
          return InkWell(
            onTap: () {
              setState(() => _selectedIndex = index);
              // 切换到全部成绩时加载数据
              if (index == 1 && _allScores == null) {
                _loadAllScores();
              }
            },
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected ? Colors.blue[50] : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.blue[300]! : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    item.icon,
                    color: isSelected ? Colors.blue[700] : Colors.grey[600],
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? Colors.blue[800]
                                : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          item.description,
                          style: TextStyle(
                            fontSize: 11,
                            color: isSelected
                                ? Colors.blue[600]
                                : Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 构建右侧内容
  Widget _buildContent() {
    switch (_selectedIndex) {
      case 0:
        return _buildNormalScoreView();
      case 1:
        return _buildAllScoresView();
      case 2:
        return _buildAnalysisView();
      case 3:
        return _buildAboutView();
      default:
        return const Center(child: Text('未知页面'));
    }
  }

  /// 平时成绩视图
  Widget _buildNormalScoreView() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载平时成绩...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMsg != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMsg!,
              style: TextStyle(color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _normalScore = null);
                _loadNormalScore();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_normalScore == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '共 ${_normalScore!.courses.length} 门课程',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        ..._normalScore!.courses.map((course) => _buildScoreCard(course)),
      ],
    );
  }

  /// 构建平时成绩卡片
  Widget _buildScoreCard(CourseSummary course) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    course.courseName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getScoreColor(course.totalScore),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${course.totalScore.toStringAsFixed(1)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.star, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '占比: ${course.totalProportion.toStringAsFixed(1)}%',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
                const SizedBox(width: 16),
                Icon(Icons.calculate, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  '折算: ${course.convertedScore.toStringAsFixed(1)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Color _getScoreColor(double score) {
    if (score >= 90) return Colors.green[600]!;
    if (score >= 80) return Colors.blue[600]!;
    if (score >= 70) return Colors.orange[600]!;
    if (score >= 60) return Colors.deepOrange[600]!;
    return Colors.red[600]!;
  }

  /// 全部成绩视图
  Widget _buildAllScoresView() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('正在加载全部成绩...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_errorMsg != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _errorMsg!,
              style: TextStyle(color: Colors.red[700]),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _allScores = null);
                _loadAllScores();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_allScores == null) {
      _loadAllScores();
      return const Center(child: CircularProgressIndicator());
    }

    final groupedScores = _allScores!.groupByTerm();
    final sortedTerms = groupedScores.keys.toList()
      ..sort((a, b) => b.compareTo(a)); // 倒序排列

    return Column(
      children: [
        // 顶部统计信息
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green[700]!, Colors.green[500]!],
            ),
            border: Border(
              bottom: BorderSide(color: Colors.green[100]!, width: 2),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem(
                icon: Icons.book,
                label: '总课程数',
                value: '${_allScores!.scores.length}',
                color: Colors.white,
              ),
              _buildStatItem(
                icon: Icons.star,
                label: '总学分',
                value: _allScores!.totalCredits.toStringAsFixed(1),
                color: Colors.white,
              ),
              _buildStatItem(
                icon: Icons.grade,
                label: '平均分',
                value: _allScores!.averageScore.toStringAsFixed(1),
                color: Colors.white,
              ),
            ],
          ),
        ),
        // 成绩列表
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: sortedTerms.length,
            itemBuilder: (context, index) {
              final term = sortedTerms[index];
              final courses = groupedScores[term]!;
              return _buildTermSection(term, courses);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: color.withOpacity(0.8)),
        ),
      ],
    );
  }

  Widget _buildTermSection(String term, List<CourseScore> courses) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        initiallyExpanded: courses == _allScores!.groupByTerm().values.first,
        title: Text(
          term,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        subtitle: Text('${courses.length}门课程'),
        children: courses
            .map((course) => _buildCourseScoreItem(course))
            .toList(),
      ),
    );
  }

  Widget _buildCourseScoreItem(CourseScore course) {
    final score = course.numericScore;
    final isPassed = course.isPassed;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      course.courseName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      course.courseCode,
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isPassed ? Colors.green[100] : Colors.red[100],
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      course.score,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isPassed ? Colors.green[800] : Colors.red[800],
                      ),
                    ),
                  ),
                  if (score != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${course.credit}学分',
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: [
              if (course.finalScore.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.book, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '期末: ${course.finalScore}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              if (course.normalScore.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.timeline, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '平时: ${course.normalScore}',
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    course.nature,
                    style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                  ),
                ],
              ),
              if (course.teacher.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      course.teacher,
                      style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 成绩分析视图
  Widget _buildAnalysisView() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.analytics, size: 80, color: Colors.orange),
          SizedBox(height: 16),
          Text(
            '成绩分析功能',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 8),
          Text('学分绩点统计、成绩趋势分析等功能开发中...', style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  /// 关于视图
  Widget _buildAboutView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 80, color: Colors.blue[300]),
            const SizedBox(height: 24),
            const Text(
              '成绩查询系统',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Text(
              '基于 JSessionId 的教务系统集成',
              style: TextStyle(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '功能说明',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildFeatureItem('平时成绩', '查看课程平时表现分数'),
                    _buildFeatureItem('全部成绩', '查看所有学期成绩记录'),
                    _buildFeatureItem('成绩分析', '学分绩点统计与分析'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green[600], size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
