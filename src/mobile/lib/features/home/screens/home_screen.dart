import 'package:flutter/material.dart';
import '../../../core/modules.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('OrderxPay')),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: appModules.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final module = appModules[index];
          return Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              title: Text(module.title),
              subtitle: Text('Section ${module.section}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pushNamed(context, module.route),
            ),
          );
        },
      ),
    );
  }
}
