import 'package:fhirant/src/widgets/backup_card.dart';
import 'package:fhirant/src/widgets/network_info_card.dart';
import 'package:fhirant/src/widgets/request_log_card.dart';
import 'package:fhirant/src/widgets/resource_counts_card.dart';
import 'package:fhirant/src/widgets/server_control_card.dart';
import 'package:flutter/material.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Column(
          children: [
            Text('FHIR ANT'),
            Text(
              'Fast Healthcare Interoperability Resources\n'
              'Agile Networking Tool',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w300),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        centerTitle: true,
        toolbarHeight: 72,
      ),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            children: [
              ServerControlCard(),
              SizedBox(height: 8),
              NetworkInfoCard(),
              SizedBox(height: 8),
              ResourceCountsCard(),
              SizedBox(height: 16),
              BackupCard(),
              SizedBox(height: 8),
              RequestLogCard(),
            ],
          ),
        ),
      ),
    );
  }
}
