import 'package:flutter/material.dart';

import 'theme/app_theme.dart';
import 'widgets/app_bottom_nav.dart';
import 'widgets/app_logo.dart';

class ReportsScreen extends StatelessWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Row(
          children: [
            AppLogo(),
            SizedBox(width: 10),
            Text('Relatórios',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.bold,
                    fontSize: 18)),
          ],
        ),
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 2),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _buildPeriodChips(),
          const SizedBox(height: 16),
          // Grade de métricas.
          Row(
            children: [
              Expanded(
                child: const _StatCard(
                  icon: Icons.forum_outlined,
                  iconColor: AppColors.primary,
                  label: 'Conversas hoje',
                  value: '128',
                  trend: '+12%',
                  trendUp: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: const _StatCard(
                  icon: Icons.check_circle_outline,
                  iconColor: AppColors.success,
                  label: 'Resolvidas',
                  value: '96',
                  trend: '+8%',
                  trendUp: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: const _StatCard(
                  icon: Icons.timer_outlined,
                  iconColor: AppColors.ai,
                  label: 'Tempo médio',
                  value: '2m 14s',
                  trend: '-5%',
                  trendUp: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: const _StatCard(
                  icon: Icons.auto_awesome,
                  iconColor: AppColors.ai,
                  label: 'Atendidas por IA',
                  value: '64%',
                  trend: '+3%',
                  trendUp: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildVolumeCard(),
          const SizedBox(height: 16),
          _buildAgentsCard(),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Dados ilustrativos — integração com a API de relatórios em breve.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: AppColors.textSecondary.withValues(alpha: 0.8),
                  fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodChips() {
    final periods = ['Hoje', '7 dias', '30 dias', 'Personalizado'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < periods.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: i == 0 ? AppColors.primary : AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                      color: i == 0 ? AppColors.primary : AppColors.border),
                ),
                child: Text(periods[i],
                    style: TextStyle(
                        color:
                            i == 0 ? Colors.white : AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildVolumeCard() {
    // Barras simples (mock) — volume por dia da semana.
    final data = <String, double>{
      'Seg': 0.55,
      'Ter': 0.70,
      'Qua': 0.45,
      'Qui': 0.85,
      'Sex': 1.0,
      'Sáb': 0.35,
      'Dom': 0.20,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Volume de conversas',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Últimos 7 dias',
              style:
                  TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            height: 130,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.entries.map((e) {
                return Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        height: 100 * e.value,
                        margin: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [AppColors.primaryDim, AppColors.primary],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(e.key,
                          style: const TextStyle(
                              color: AppColors.textSecondary, fontSize: 11)),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAgentsCard() {
    final agents = <Map<String, dynamic>>[
      {'name': 'Douglas Carrilo', 'count': 42, 'ratio': 1.0},
      {'name': 'Letícia Souza', 'count': 31, 'ratio': 0.74},
      {'name': 'Henrique Souza', 'count': 23, 'ratio': 0.55},
      {'name': 'Atendimento IA', 'count': 82, 'ratio': 0.95, 'ai': true},
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Desempenho por atendente',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          ...agents.map((a) {
            final isAi = a['ai'] == true;
            final color = isAi ? AppColors.ai : AppColors.primary;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isAi) ...[
                        const Icon(Icons.auto_awesome,
                            size: 14, color: AppColors.ai),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(a['name'] as String,
                            style: const TextStyle(
                                color: AppColors.textPrimary, fontSize: 13)),
                      ),
                      Text('${a['count']}',
                          style: TextStyle(
                              color: color,
                              fontSize: 13,
                              fontWeight: FontWeight.w700)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: a['ratio'] as double,
                      minHeight: 6,
                      backgroundColor: AppColors.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.trend,
    required this.trendUp,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final String trend;
  final bool trendUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const Spacer(),
              Row(
                children: [
                  Icon(trendUp ? Icons.trending_up : Icons.trending_down,
                      size: 14, color: AppColors.success),
                  const SizedBox(width: 2),
                  Text(trend,
                      style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 11,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(value,
              style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }
}
