import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';

import '../../../core/services/prescription_storage_service.dart';

class SavedReportsPage extends StatefulWidget {
  const SavedReportsPage({super.key});

  static const routePath = '/saved-reports';

  @override
  State<SavedReportsPage> createState() => _SavedReportsPageState();
}

class _SavedReportsPageState extends State<SavedReportsPage> {
  List<Map<String, dynamic>> _reports = <Map<String, dynamic>>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final reports = await PrescriptionStorageService.getReportsBySources(
      const {'result_pdf', 'report_quick_action'},
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _reports = reports;
      _isLoading = false;
    });
  }

  Future<void> _openReport(Map<String, dynamic> report) async {
    final filePath = report['filePath']?.toString() ?? '';
    if (filePath.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('prescriptions_open_failed'.tr(args: ['']))),
      );
      return;
    }

    final file = File(filePath);
    if (!await file.exists()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('prescriptions_file_missing'.tr())),
      );
      return;
    }

    final result = await OpenFilex.open(filePath);
    if (!mounted) {
      return;
    }
    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('prescriptions_open_failed'.tr(args: [result.message]))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/dashboard');
            }
          },
        ),
        title: Text('dashboard_report'.tr()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _reports.isEmpty
              ? Center(
                  child: Text('dashboard_download_soon'.tr()),
                )
              : ListView.separated(
                  itemCount: _reports.length,
                  separatorBuilder: (_, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final report = _reports[index];
                    final addedAt = DateTime.tryParse(
                          report['addedAt']?.toString() ?? '',
                        ) ??
                        DateTime.now();

                    return ListTile(
                      onTap: () => _openReport(report),
                      leading: const Icon(Icons.picture_as_pdf),
                      title: Text(report['fileName']?.toString() ?? 'report.pdf'),
                      subtitle: Text(
                        '${DateFormat('yyyy-MM-dd HH:mm').format(addedAt)}\n${report['filePath'] ?? ''}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.open_in_new),
                    );
                  },
                ),
    );
  }
}
