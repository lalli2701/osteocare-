import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/services/prescription_storage_service.dart';

class PrescriptionsPage extends StatefulWidget {
  const PrescriptionsPage({super.key});

  static const routePath = '/prescriptions';

  @override
  State<PrescriptionsPage> createState() => _PrescriptionsPageState();
}

class _PrescriptionsPageState extends State<PrescriptionsPage> {
  List<Map<String, dynamic>> _reports = <Map<String, dynamic>>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadReports();
  }

  Future<void> _loadReports() async {
    final reports = await PrescriptionStorageService.getReportsBySources(
      const {'files', 'camera'},
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _reports = reports;
      _isLoading = false;
    });
  }

  Future<void> _addFromFiles() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowMultiple: false,
      allowedExtensions: <String>['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
    );

    if (picked == null || picked.files.isEmpty || picked.files.first.path == null) {
      return;
    }

    final sourcePath = picked.files.first.path!;
    final reportsDir = await _reportsDir();
    final name = p.basename(sourcePath);
    final targetPath = p.join(reportsDir.path, '${DateTime.now().millisecondsSinceEpoch}_$name');

    await File(sourcePath).copy(targetPath);

    await PrescriptionStorageService.addReport(
      filePath: targetPath,
      fileName: p.basename(targetPath),
      source: 'files',
    );

    await _loadReports();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('prescriptions_added_from_files'.tr())),
    );
  }

  Future<void> _addFromCamera() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);

    if (image == null) {
      return;
    }

    final reportsDir = await _reportsDir();
    final targetPath = p.join(
      reportsDir.path,
      'camera_${DateTime.now().millisecondsSinceEpoch}${p.extension(image.path).isEmpty ? '.jpg' : p.extension(image.path)}',
    );

    await File(image.path).copy(targetPath);

    await PrescriptionStorageService.addReport(
      filePath: targetPath,
      fileName: p.basename(targetPath),
      source: 'camera',
    );

    await _loadReports();

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('prescriptions_added_from_camera'.tr())),
    );
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

  Future<Directory> _reportsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'prescriptions'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
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
        title: Text('prescriptions_title'.tr()),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _addFromFiles,
                          icon: const Icon(Icons.folder_open),
                          label: Text('prescriptions_add_folder'.tr()),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _addFromCamera,
                          icon: const Icon(Icons.camera_alt),
                          label: Text('prescriptions_camera'.tr()),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _reports.isEmpty
                      ? Center(
                          child: Text('prescriptions_empty'.tr()),
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
                              leading: Icon(
                                (report['fileName']?.toString().toLowerCase().endsWith('.pdf') ?? false)
                                    ? Icons.picture_as_pdf
                                    : Icons.description,
                              ),
                              title: Text(report['fileName']?.toString() ?? 'report'),
                              subtitle: Text(
                                '${report['source'] ?? 'unknown'} • ${DateFormat('yyyy-MM-dd HH:mm').format(addedAt)}\n${report['filePath'] ?? ''}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(Icons.open_in_new),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }
}
