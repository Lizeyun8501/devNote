import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:intl/intl.dart';

/// 笔记数据模型（简化版，用于 PDF 导出）
///
/// ## 借鉴的开源项目
/// - **pdf.dart 库** ([GitHub](https://github.com/DavBfr/dart_pdf)):
///   Dart 原生 PDF 生成库，支持丰富的排版功能
/// - **wkhtmltopdf** ([官网](https://wkhtmltopdf.org/)):
///   借鉴其 HTML 转 PDF 的布局理念，支持页眉页脚、分页等
///
/// ## 实现说明
/// 使用 pdf.dart 库生成 PDF，支持单篇笔记导出和批量导出。
/// 包含页眉、页脚、目录等标准 PDF 特性。
class NoteModel {
  final String id;
  final String title;
  final String content;
  final String folderId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteModel({
    required this.id,
    required this.title,
    required this.content,
    required this.folderId,
    required this.createdAt,
    required this.updatedAt,
  });
}

/// PDF 导出服务
///
/// ## 借鉴的开源项目
/// - **pdf.dart 库** ([GitHub](https://github.com/DavBfr/dart_pdf)):
///   借鉴其 pw.Document 文档构建 API、pw.Text 文本排版、pw.Table 表格布局等
/// - **wkhtmltopdf** ([官网](https://wkhtmltopdf.org/)):
///   借鉴其页面布局理念（页眉、页脚、页码、分页控制）
///
/// ## 实现说明
/// 使用 pdf.dart 库生成标准 PDF 文件，特性包括：
/// - 自定义页眉页脚（包含标题和页码）
/// - 支持分页控制
/// - 支持 Markdown 风格的简单文本格式化
/// - 批量导出时自动生成目录
class PdfExportService {
  /// 将单篇笔记导出为 PDF 字节数据
  ///
  /// 借鉴 pdf.dart 的 Document 构建模式：
  /// 使用 pw.MultiPage 支持自动分页，pw.Header 和 pw.Text 构建内容
  Future<Uint8List> exportNoteAsPdf(NoteModel note) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        header: (context) => _buildHeader(note.title, context),
        footer: (context) => _buildFooter(context),
        build: (context) => [
          // 标题
          pw.Header(
            level: 0,
            text: note.title,
            textStyle: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          // 元数据
          pw.Text(
            '创建时间: ${_formatDate(note.createdAt)}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Text(
            '更新时间: ${_formatDate(note.updatedAt)}',
            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.Divider(),
          pw.SizedBox(height: 16),
          // 正文内容（借鉴 wkhtmltopdf 的段落排版）
          ..._buildContentWidgets(note.content),
        ],
      ),
    );

    return pdf.save();
  }

  /// 将多篇笔记导出为单个 PDF 文件
  ///
  /// 借鉴 wkhtmltopdf 的多文档合并理念：
  /// 自动生成目录页，每篇笔记从新页开始
  Future<void> exportNotesAsPdf(
    List<NoteModel> notes,
    String outputPath,
  ) async {
    final pdf = pw.Document();

    // 添加目录页
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Header(
              level: 0,
              text: '笔记目录',
              textStyle: pw.TextStyle(
                fontSize: 28,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 16),
            ...notes.asMap().entries.map((entry) {
              final index = entry.key + 1;
              final note = entry.value;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Row(
                  children: [
                    pw.Text(
                      '$index. ',
                      style: pw.TextStyle(fontSize: 14),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        note.title,
                        style: pw.TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );

    // 添加每篇笔记（借鉴 pdf.dart 的分页机制）
    for (final note in notes) {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => _buildHeader(note.title, context),
          footer: (context) => _buildFooter(context),
          build: (context) => [
            pw.Header(
              level: 0,
              text: note.title,
              textStyle: pw.TextStyle(
                fontSize: 24,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              '创建时间: ${_formatDate(note.createdAt)}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Text(
              '更新时间: ${_formatDate(note.updatedAt)}',
              style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.Divider(),
            pw.SizedBox(height: 16),
            ..._buildContentWidgets(note.content),
          ],
        ),
      );
    }

    // 保存到文件
    final file = File(outputPath);
    await file.writeAsBytes(await pdf.save());
  }

  // ========== 私有方法 ==========

  /// 构建页眉（借鉴 wkhtmltopdf 的页眉模板）
  pw.Widget _buildHeader(String title, pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(bottom: 16),
      padding: const pw.EdgeInsets.only(bottom: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey600,
          fontStyle: pw.FontStyle.italic,
        ),
        maxLines: 1,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  /// 构建页脚（包含页码，借鉴 wkhtmltopdf 的页脚页码）
  pw.Widget _buildFooter(pw.Context context) {
    return pw.Container(
      alignment: pw.Alignment.center,
      margin: const pw.EdgeInsets.only(top: 16),
      padding: const pw.EdgeInsets.only(top: 8),
      decoration: pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
        ),
      ),
      child: pw.Text(
        '第 ${context.pageNumber} 页 / 共 ${context.pagesCount} 页',
        style: pw.TextStyle(
          fontSize: 8,
          color: PdfColors.grey600,
        ),
      ),
    );
  }

  /// 构建正文内容 Widgets
  ///
  /// 将笔记内容按行分割，借鉴 wkhtmltopdf 的文本解析逻辑：
  /// 识别简单的 Markdown 格式（标题、列表、代码块）
  List<pw.Widget> _buildContentWidgets(String content) {
    final widgets = <pw.Widget>[];
    final lines = content.split('\n');
    bool inCodeBlock = false;
    final codeLines = <String>[];

    for (final line in lines) {
      // 代码块处理
      if (line.trim().startsWith('```')) {
        if (inCodeBlock) {
          // 结束代码块
          widgets.add(_buildCodeBlock(codeLines.join('\n')));
          codeLines.clear();
          inCodeBlock = false;
        } else {
          inCodeBlock = true;
        }
        continue;
      }

      if (inCodeBlock) {
        codeLines.add(line);
        continue;
      }

      // 标题处理（借鉴 Markdown 标题语法）
      if (line.startsWith('# ')) {
        widgets.add(pw.SizedBox(height: 16));
        widgets.add(
          pw.Text(
            line.substring(2),
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 8));
      } else if (line.startsWith('## ')) {
        widgets.add(pw.SizedBox(height: 12));
        widgets.add(
          pw.Text(
            line.substring(3),
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 6));
      } else if (line.startsWith('### ')) {
        widgets.add(pw.SizedBox(height: 10));
        widgets.add(
          pw.Text(
            line.substring(4),
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
              fontStyle: pw.FontStyle.italic,
            ),
          ),
        );
        widgets.add(pw.SizedBox(height: 4));
      }
      // 列表处理
      else if (line.startsWith('- ') || line.startsWith('* ')) {
        widgets.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(left: 16, bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('• ', style: pw.TextStyle(fontSize: 12)),
                pw.Expanded(
                  child: pw.Text(
                    line.substring(2),
                    style: pw.TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        );
      }
      // 分隔线
      else if (line.trim() == '---' || line.trim() == '***') {
        widgets.add(pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 8),
          child: pw.Divider(color: PdfColors.grey400),
        ));
      }
      // 空行
      else if (line.trim().isEmpty) {
        widgets.add(pw.SizedBox(height: 8));
      }
      // 普通段落
      else {
        widgets.add(
          pw.Text(
            line,
            style: pw.TextStyle(fontSize: 12),
          ),
        );
        widgets.add(pw.SizedBox(height: 4));
      }
    }

    // 处理未闭合的代码块
    if (codeLines.isNotEmpty) {
      widgets.add(_buildCodeBlock(codeLines.join('\n')));
    }

    return widgets;
  }

  /// 构建代码块 Widget（借鉴 VS Code 的代码块样式）
  pw.Widget _buildCodeBlock(String code) {
    return pw.Container(
      margin: const pw.EdgeInsets.symmetric(vertical: 8),
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(4),
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Text(
        code,
        style: pw.TextStyle(
          fontSize: 10,
        ),
      ),
    );
  }

  /// 格式化日期
  String _formatDate(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }
}
