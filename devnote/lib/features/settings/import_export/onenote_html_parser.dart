// OneNote HTML 解析器 —— 解析 OneNote 导出的 HTML 文件
// 借鉴 OneNote 导出格式规范：https://learn.microsoft.com/en-us/graph/api/resources/onenote-api-overview
//
// OneNote 导出的 HTML 特征：
// 1. 页面标题位于 <title> 标签或第一个 <h1>
// 2. 内容块使用 <div data-id="..."> 包裹
// 3. 图片使用 <img data-src="..." data-render-src="..."> 引用
// 4. 表格使用 <table> 标签，可能带有 style 属性
// 5. OneNote 标签系统：通过 <img data-tag="..."> 标记（如待办、重要、问题等）
// 6. 创建/修改时间通常在 HTML meta 标签或 front matter 中

import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart' as dom;

/// OneNote 页面解析结果
class OneNotePage {
  /// 页面标题
  final String title;

  /// 创建时间
  final DateTime? createdDateTime;

  /// 修改时间
  final DateTime? modifiedDateTime;

  /// 解析出的内容块
  final List<OneNoteBlock> blocks;

  /// 页面中引用的图片列表
  final List<OneNoteImage> images;

  /// 页面元数据（来自 meta 标签或 front matter）
  final Map<String, String> metadata;

  const OneNotePage({
    required this.title,
    this.createdDateTime,
    this.modifiedDateTime,
    this.blocks = const [],
    this.images = const [],
    this.metadata = const {},
  });
}

/// OneNote 内容块的中间表示
/// 由 OneNoteHtmlParser 解析产生，由 OneNoteImportService 转换为 DevNote BlockModel
class OneNoteBlock {
  /// 块类型（对应 DevNote BlockType）
  final OneNoteBlockType type;

  /// 文本内容
  final String content;

  /// 标题级别（1-6，仅 heading 类型有效）
  final int? headingLevel;

  /// 代码语言（仅 code 类型有效）
  final String? language;

  /// 列表项（仅 list 类型有效）
  final List<String> listItems;

  /// 表格数据（仅 table 类型有效，外层为行，内层为单元格）
  final List<List<String>> tableRows;

  /// 表格是否包含表头
  final bool tableHasHeader;

  /// 图片引用（仅 image 类型有效）
  final OneNoteImage? image;

  /// OneNote data-id（用于追踪原始位置）
  final String? dataId;

  const OneNoteBlock({
    required this.type,
    this.content = '',
    this.headingLevel,
    this.language,
    this.listItems = const [],
    this.tableRows = const [],
    this.tableHasHeader = false,
    this.image,
    this.dataId,
  });
}

/// OneNote 块类型枚举（映射到 DevNote BlockType）
enum OneNoteBlockType {
  paragraph,
  heading,
  image,
  table,
  unorderedList,
  orderedList,
  code,
  quote,
  taskList,
  divider,
}

/// OneNote 图片引用
class OneNoteImage {
  /// 图片源路径（data-src 优先，回退到 src）
  final String src;

  /// 图片替代文本
  final String alt;

  /// 图片标题
  final String? title;

  /// 是否为 OneNote 标签图标（如待办勾选框、重要标记等）
  final bool isTagIcon;

  /// 标签名称（仅当 isTagIcon 为 true 时有效，如 "to-do"、"important"）
  final String? tagName;

  const OneNoteImage({
    required this.src,
    this.alt = '',
    this.title,
    this.isTagIcon = false,
    this.tagName,
  });
}

/// OneNote HTML 解析器
///
/// 解析 OneNote 导出的 HTML 文件，提取标题、元数据、内容块和图片引用。
/// 处理 OneNote 特有的 HTML 结构：
/// - `<div data-id="...">`：内容块容器
/// - `<img data-src="...">`：图片引用（data-src 优先于 src）
/// - `<table>`：表格（保留 OneNote 表格样式）
/// - `<img data-tag="...">`：OneNote 标签系统（待办、重要、问题等）
class OneNoteHtmlParser {
  /// 解析 HTML 字符串，返回 OneNotePage 对象
  OneNotePage parse(String html) {
    final document = html_parser.parse(html);

    // 提取标题
    final title = _extractTitle(document);

    // 提取元数据（meta 标签）
    final metadata = _extractMetadata(document);

    // 提取创建/修改时间
    final createdDateTime = _parseDateTime(metadata['created']) ??
        _parseDateTime(metadata['date']);
    final modifiedDateTime = _parseDateTime(metadata['modified']) ??
        _parseDateTime(metadata['last-modified']);

    // 提取内容块
    final blocks = <OneNoteBlock>[];
    final images = <OneNoteImage>[];

    // 优先解析 body 下的内容，OneNote 导出的主要内容在 body 中
    final body = document.body;
    if (body != null) {
      _parseNode(body, blocks, images);
    }

    return OneNotePage(
      title: title,
      createdDateTime: createdDateTime,
      modifiedDateTime: modifiedDateTime,
      blocks: blocks,
      images: images,
      metadata: metadata,
    );
  }

  /// 提取页面标题
  /// 优先级：<title> 标签 > 第一个 <h1> > 第一个 <h2> > "Untitled"
  String _extractTitle(dom.Document document) {
    // 1. 尝试从 <title> 标签提取
    final titleTag = document.querySelector('title');
    if (titleTag != null && titleTag.text.trim().isNotEmpty) {
      return titleTag.text.trim();
    }

    // 2. 尝试从第一个 <h1> 提取
    final h1 = document.querySelector('h1');
    if (h1 != null && h1.text.trim().isNotEmpty) {
      return h1.text.trim();
    }

    // 3. 尝试从第一个 <h2> 提取
    final h2 = document.querySelector('h2');
    if (h2 != null && h2.text.trim().isNotEmpty) {
      return h2.text.trim();
    }

    return 'Untitled';
  }

  /// 提取 meta 标签元数据
  Map<String, String> _extractMetadata(dom.Document document) {
    final metadata = <String, String>{};
    final metaTags = document.querySelectorAll('meta');
    for (final meta in metaTags) {
      final name = meta.attributes['name'] ?? meta.attributes['property'];
      final content = meta.attributes['content'];
      if (name != null && content != null) {
        metadata[name.toLowerCase()] = content;
      }
    }
    return metadata;
  }

  /// 解析日期时间字符串
  /// 支持 ISO 8601 格式和常见 OneNote 导出格式
  DateTime? _parseDateTime(String? value) {
    if (value == null || value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// 递归解析 DOM 节点，提取内容块和图片
  void _parseNode(
    dom.Node node,
    List<OneNoteBlock> blocks,
    List<OneNoteImage> images, {
    String? parentDataId,
  }) {
    if (node is dom.Element) {
      final tagName = node.localName?.toLowerCase() ?? '';
      final dataId = node.attributes['data-id'] ?? parentDataId;

      // 处理 OneNote 标签图标（<img data-tag="...">）
      if (tagName == 'img') {
        final image = _parseImage(node);
        images.add(image);
        if (image.isTagIcon) {
          // 标签图标不作为独立块，跳过
          return;
        }
        blocks.add(OneNoteBlock(
          type: OneNoteBlockType.image,
          image: image,
          dataId: dataId,
        ));
        return;
      }

      // 标题块
      if (_isHeading(tagName)) {
        final level = int.tryParse(tagName.substring(1)) ?? 1;
        final text = node.text.trim();
        if (text.isNotEmpty) {
          blocks.add(OneNoteBlock(
            type: OneNoteBlockType.heading,
            content: text,
            headingLevel: level,
            dataId: dataId,
          ));
        }
        return;
      }

      // 段落块
      if (tagName == 'p') {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          blocks.add(OneNoteBlock(
            type: OneNoteBlockType.paragraph,
            content: text,
            dataId: dataId,
          ));
        }
        return;
      }

      // 代码块
      if (tagName == 'pre') {
        final codeElement = node.querySelector('code');
        final text = (codeElement?.text ?? node.text).trim();
        final language = codeElement?.className
            .split(' ')
            .where((c) => c.startsWith('language-'))
            .map((c) => c.substring(9))
            .firstOrNull;
        if (text.isNotEmpty) {
          blocks.add(OneNoteBlock(
            type: OneNoteBlockType.code,
            content: text,
            language: language,
            dataId: dataId,
          ));
        }
        return;
      }

      // 引用块
      if (tagName == 'blockquote') {
        final text = node.text.trim();
        if (text.isNotEmpty) {
          blocks.add(OneNoteBlock(
            type: OneNoteBlockType.quote,
            content: text,
            dataId: dataId,
          ));
        }
        return;
      }

      // 无序列表
      if (tagName == 'ul') {
        final items = <String>[];
        final isTaskList = _parseList(node, items);
        if (items.isNotEmpty) {
          blocks.add(OneNoteBlock(
            type: isTaskList
                ? OneNoteBlockType.taskList
                : OneNoteBlockType.unorderedList,
            listItems: items,
            dataId: dataId,
          ));
        }
        return;
      }

      // 有序列表
      if (tagName == 'ol') {
        final items = <String>[];
        _parseList(node, items);
        if (items.isNotEmpty) {
          blocks.add(OneNoteBlock(
            type: OneNoteBlockType.orderedList,
            listItems: items,
            dataId: dataId,
          ));
        }
        return;
      }

      // 表格
      if (tagName == 'table') {
        final tableData = _parseTable(node);
        if (tableData.rows.isNotEmpty) {
          blocks.add(OneNoteBlock(
            type: OneNoteBlockType.table,
            tableRows: tableData.rows,
            tableHasHeader: tableData.hasHeader,
            dataId: dataId,
          ));
        }
        return;
      }

      // 分隔线
      if (tagName == 'hr') {
        blocks.add(OneNoteBlock(
          type: OneNoteBlockType.divider,
          dataId: dataId,
        ));
        return;
      }

      // div 容器：递归解析子节点
      // OneNote 使用 <div data-id="..."> 包裹内容块
      if (tagName == 'div') {
        for (final child in node.nodes) {
          _parseNode(child, blocks, images, parentDataId: dataId);
        }
        return;
      }

      // 其他块级元素：递归解析子节点
      for (final child in node.nodes) {
        _parseNode(child, blocks, images, parentDataId: dataId);
      }
    } else if (node is dom.Text) {
      // 纯文本节点：如果非空且非空白，作为段落块
      final text = node.text.trim();
      if (text.isNotEmpty) {
        blocks.add(OneNoteBlock(
          type: OneNoteBlockType.paragraph,
          content: text,
        ));
      }
    }
  }

  /// 判断是否为标题标签
  bool _isHeading(String tagName) {
    return tagName.length == 2 &&
        tagName.startsWith('h') &&
        int.tryParse(tagName[1]) != null;
  }

  /// 解析图片元素
  OneNoteImage _parseImage(dom.Element img) {
    // OneNote 使用 data-src 存储原始图片路径，src 可能是占位符
    final src = img.attributes['data-src'] ??
        img.attributes['data-render-src'] ??
        img.attributes['src'] ??
        '';

    final alt = img.attributes['alt'] ?? '';
    final title = img.attributes['title'];

    // 检查是否为 OneNote 标签图标
    final dataTag = img.attributes['data-tag'];
    final isTagIcon = dataTag != null && dataTag.isNotEmpty;

    return OneNoteImage(
      src: src,
      alt: alt,
      title: title,
      isTagIcon: isTagIcon,
      tagName: isTagIcon ? dataTag : null,
    );
  }

  /// 解析列表元素，返回是否为任务列表
  /// OneNote 任务列表项使用 <img data-tag="to-do"> 或 <img data-tag="to-do:completed"> 标记
  bool _parseList(dom.Element listElement, List<String> items) {
    var isTaskList = false;
    final listItems = listElement.querySelectorAll('li');
    for (final li in listItems) {
      // 检查是否包含 OneNote 标签图标（任务列表标记）
      final tagImgs = li.querySelectorAll('img[data-tag]');
      for (final img in tagImgs) {
        final tag = img.attributes['data-tag'] ?? '';
        if (tag.startsWith('to-do')) {
          isTaskList = true;
          break;
        }
      }

      // 提取列表项文本（移除标签图标后的纯文本）
      final text = li.text.trim();
      if (text.isNotEmpty) {
        // 任务列表项添加 [ ] 或 [x] 前缀以保留完成状态
        if (isTaskList) {
          final isCompleted = tagImgs.any((img) =>
              (img.attributes['data-tag'] ?? '').contains('completed'));
          items.add('${isCompleted ? '[x]' : '[ ]'} $text');
        } else {
          items.add(text);
        }
      }
    }
    return isTaskList;
  }

  /// 解析表格元素
  _TableData _parseTable(dom.Element tableElement) {
    final rows = <List<String>>[];
    var hasHeader = false;

    // 解析表头
    final thead = tableElement.querySelector('thead');
    if (thead != null) {
      final headerRows = thead.querySelectorAll('tr');
      for (final tr in headerRows) {
        final cells = <String>[];
        for (final cell in tr.querySelectorAll('th, td')) {
          cells.add(cell.text.trim());
        }
        if (cells.isNotEmpty) {
          rows.add(cells);
          hasHeader = true;
        }
      }
    }

    // 解析表体
    final tbody = tableElement.querySelector('tbody') ?? tableElement;
    final bodyRows = tbody.querySelectorAll('tr');
    for (final tr in bodyRows) {
      // 跳过 thead 中的行（避免重复）
      if (tr.parent?.localName?.toLowerCase() == 'thead') continue;
      final cells = <String>[];
      for (final cell in tr.querySelectorAll('th, td')) {
        cells.add(cell.text.trim());
      }
      if (cells.isNotEmpty) {
        rows.add(cells);
      }
    }

    return _TableData(rows: rows, hasHeader: hasHeader);
  }
}

/// 表格解析结果
class _TableData {
  final List<List<String>> rows;
  final bool hasHeader;

  const _TableData({required this.rows, required this.hasHeader});
}
