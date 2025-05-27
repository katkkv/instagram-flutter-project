import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fl_chart/fl_chart.dart';
import '../data/app_themes.dart';
import 'package:shared_preferences/shared_preferences.dart';

class StatisticsScreen extends StatefulWidget {
  final String userId;
  final ValueNotifier<ThemeData> themeNotifier;

  const StatisticsScreen({
    Key? key,
    required this.userId,
    required this.themeNotifier,
  }) : super(key: key);

  @override
  _StatisticsScreenState createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with SingleTickerProviderStateMixin {
  int totalLikesReceived = 0;
  int totalFollowers = 0;
  int totalLikesGiven = 0;
  int totalComments = 0;
  bool isLoading = true;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Данные для графиков
  List<Map<String, dynamic>> likesOverTime = [];
  List<Map<String, dynamic>> followersOverTime = [];
  List<Map<String, dynamic>> commentsOverTime = [];

  @override
  void initState() {
    super.initState();
    fetchStatistics();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _fadeAnimation = CurvedAnimation(parent: _animationController, curve: Curves.easeIn);
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> fetchStatistics() async {
    setState(() => isLoading = true);
    try {
      // Получение общего количества лайков на постах пользователя (фото и видео)
      final likesReceivedResponse = await Supabase.instance.client
          .rpc('get_total_likes_received', params: {'user_id_param': widget.userId});

      // Получение количества подписчиков
      final followersResponse = await Supabase.instance.client
          .from('subscriptions')
          .select('id')
          .eq('following_id', widget.userId)
          .count();

      // Получение количества поставленных лайков
      final likesGivenResponse = await Supabase.instance.client
          .from('video_likes')
          .select('id')
          .eq('user_id', widget.userId)
          .count();

      // Получение общего количества комментариев на постах пользователя (фото и видео)
      final commentsReceivedResponse = await Supabase.instance.client
          .rpc('get_total_comments_received', params: {'user_id_param': widget.userId});

      // Данные по времени (группировка по месяцам)
      final likesOverTimeResponse = await Supabase.instance.client
          .rpc('get_likes_by_month', params: {'user_id_param': widget.userId});

      final followersOverTimeResponse = await Supabase.instance.client
          .rpc('get_followers_by_month', params: {'user_id_param': widget.userId});

      final commentsOverTimeResponse = await Supabase.instance.client
          .rpc('get_comments_by_month', params: {'user_id_param': widget.userId});

      if (mounted) {
        setState(() {
          totalLikesReceived = likesReceivedResponse ?? 0;
          totalFollowers = followersResponse.count;
          totalLikesGiven = likesGivenResponse.count;
          totalComments = commentsReceivedResponse ?? 0;
          likesOverTime = List<Map<String, dynamic>>.from(likesOverTimeResponse ?? []);
          followersOverTime = List<Map<String, dynamic>>.from(followersOverTimeResponse ?? []);
          commentsOverTime = List<Map<String, dynamic>>.from(commentsOverTimeResponse ?? []);
          isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить статистику: $e')),
        );
        setState(() => isLoading = false);
      }
    }
  }

  void _toggleTheme(ThemeData newTheme) async {
    widget.themeNotifier.value = newTheme;
    final prefs = await SharedPreferences.getInstance();
    if (newTheme == AppThemes.lightTheme) {
      await prefs.setInt('themeMode', 0);
    } else if (newTheme == AppThemes.darkTheme) {
      await prefs.setInt('themeMode', 1);
    } else if (newTheme == AppThemes.pinkTheme) {
      await prefs.setInt('themeMode', 2);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            backgroundColor: widget.themeNotifier.value.scaffoldBackgroundColor,
            elevation: 0,
            pinned: true,
            leading: IconButton(
              icon: Icon(Icons.arrow_back, color: widget.themeNotifier.value.iconTheme.color),
              onPressed: () => Navigator.pop(context),
            ),
            title: Text(
              'Статистика',
              style: TextStyle(
                color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            actions: [
              PopupMenuButton<ThemeData>(
                icon: Icon(Icons.color_lens, color: widget.themeNotifier.value.iconTheme.color),
                color: widget.themeNotifier.value.cardColor,
                onSelected: _toggleTheme,
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: AppThemes.lightTheme,
                    child: Text('Светлая', style: TextStyle(color: widget.themeNotifier.value.textTheme.bodyLarge?.color)),
                  ),
                  PopupMenuItem(
                    value: AppThemes.darkTheme,
                    child: Text('Темная', style: TextStyle(color: widget.themeNotifier.value.textTheme.bodyLarge?.color)),
                  ),
                  PopupMenuItem(
                    value: AppThemes.pinkTheme,
                    child: Text('Розовая', style: TextStyle(color: widget.themeNotifier.value.textTheme.bodyLarge?.color)),
                  ),

                ],
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: isLoading
                ? const Center(child: CircularProgressIndicator())
                : Padding(
              padding: const EdgeInsets.all(16.0),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StatisticCard(
                      title: 'Поставлено лайков',
                      value: totalLikesReceived,
                      icon: Icons.favorite,
                      themeNotifier: widget.themeNotifier,
                      animationDelay: 0,
                    ),
                    const SizedBox(height: 16),
                    StatisticCard(
                      title: 'Подписчиков',
                      value: totalFollowers,
                      icon: Icons.people,
                      themeNotifier: widget.themeNotifier,
                      animationDelay: 100,
                    ),
                    const SizedBox(height: 16),
                    StatisticCard(
                      title: 'Получено лайков',
                      value: totalLikesGiven,
                      icon: Icons.favorite_border, // Fixed 'firmly' to 'icon'
                      themeNotifier: widget.themeNotifier,
                      animationDelay: 200,
                    ),
                    const SizedBox(height: 16),
                    StatisticCard(
                      title: 'Написано комментариев',
                      value: totalComments,
                      icon: Icons.comment,
                      themeNotifier: widget.themeNotifier,
                      animationDelay: 300,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'Динамика активности',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                      ),
                    ),
                    const SizedBox(height: 16),
                    ActivityChart(
                      title: 'Лайки по месяцам',
                      data: likesOverTime,
                      color: Colors.red,
                      themeNotifier: widget.themeNotifier,
                    ),
                    const SizedBox(height: 16),
                    ActivityChart(
                      title: 'Подписчики по месяцам',
                      data: followersOverTime,
                      color: Colors.blue,
                      themeNotifier: widget.themeNotifier,
                    ),
                    const SizedBox(height: 16),
                    ActivityChart(
                      title: 'Комментарии по месяцам',
                      data: commentsOverTime,
                      color: Colors.green,
                      themeNotifier: widget.themeNotifier,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class StatisticCard extends StatefulWidget {
  final String title;
  final int value;
  final IconData icon;
  final ValueNotifier<ThemeData> themeNotifier;
  final int animationDelay;

  const StatisticCard({
    Key? key,
    required this.title,
    required this.value,
    required this.icon,
    required this.themeNotifier,
    required this.animationDelay,
  }) : super(key: key);

  @override
  _StatisticCardState createState() => _StatisticCardState();
}

class _StatisticCardState extends State<StatisticCard> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    Future.delayed(Duration(milliseconds: widget.animationDelay), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTap: () {
          _controller.reverse().then((value) => _controller.forward());
        },
        child: Container(
          padding: const EdgeInsets.all(20),

          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: widget.themeNotifier.value.primaryColor.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  color: widget.themeNotifier.value.primaryColor,
                  size: 30,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.value.toString(),
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: widget.themeNotifier.value.textTheme.bodyLarge?.color,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ActivityChart extends StatelessWidget {
  final String title;
  final List<Map<String, dynamic>> data;
  final Color color;
  final ValueNotifier<ThemeData> themeNotifier;

  const ActivityChart({
    Key? key,
    required this.title,
    required this.data,
    required this.color,
    required this.themeNotifier,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: themeNotifier.value.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: themeNotifier.value.textTheme.bodyLarge?.color,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  horizontalInterval: 10,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: themeNotifier.value.dividerColor.withOpacity(0.5),
                      strokeWidth: 1,
                    );
                  },
                  getDrawingVerticalLine: (value) {
                    return FlLine(
                      color: themeNotifier.value.dividerColor.withOpacity(0.5),
                      strokeWidth: 1,
                    );
                  },
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      interval: 10,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          value.toInt().toString(),
                          style: TextStyle(
                            color: themeNotifier.value.textTheme.bodyLarge?.color,
                            fontSize: 12,
                          ),
                        );
                      },
                      reservedSize: 40,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        if (value.toInt() >= data.length) return const Text('');
                        return Text(
                          data[value.toInt()]['month'].substring(2, 7),
                          style: TextStyle(
                            color: themeNotifier.value.textTheme.bodyLarge?.color,
                            fontSize: 12,
                          ),
                        );
                      },
                      reservedSize: 30,
                    ),
                  ),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(
                  show: true,
                  border: Border.all(
                    color: themeNotifier.value.dividerColor,
                    width: 1,
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: data.asMap().entries.map((entry) {
                      return FlSpot(entry.key.toDouble(), entry.value['count'].toDouble());
                    }).toList(),
                    isCurved: true,
                    color: color,
                    barWidth: 4,
                    belowBarData: BarAreaData(
                      show: true,
                      color: color.withOpacity(0.2),
                    ),
                    dotData: const FlDotData(show: false),
                  ),
                ],
                minY: 0,
                maxY: (data.isNotEmpty ? data.map((e) => e['count'] as int).reduce((a, b) => a > b ? a : b).toDouble() * 1.2 : 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}