// DevNote Web Clipper —— content script
//
// 负责：
//   1. 监听来自 background / popup 的 EXTRACT_CONTENT 消息，按模式提取页面内容。
//   2. 提供 4 种剪藏模式：full_page / simplified_article / bookmark / selection。
//   3. 将提取出的 HTML 转换为 Markdown（简化版转换器）。
//   4. 监听 background 回传的 CLIP_RESULT，给出页面内提示。

(function () {
  'use strict';

  const CLIP_MODE = {
    FULL_PAGE: 'full_page',
    SIMPLIFIED_ARTICLE: 'simplified_article',
    BOOKMARK: 'bookmark',
    SELECTION: 'selection',
  };

  // 避免重复注入导致多次绑定
  if (window.__devnoteClipperInjected) {
    return;
  }
  window.__devnoteClipperInjected = true;

  chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
    if (!msg || msg.type !== 'EXTRACT_CONTENT') return;
    try {
      const payload = extract(msg.mode);
      sendResponse({ ok: true, payload });
    } catch (err) {
      sendResponse({ ok: false, error: err.message });
    }
  });

  // 监听剪藏结果，在页面上给出轻量提示
  chrome.runtime.onMessage.addListener((msg) => {
    if (!msg || msg.type !== 'CLIP_RESULT') return;
    showOverlay(msg.payload && msg.payload.ok ? '已剪藏到 DevNote' : `剪藏失败：${msg.payload && msg.payload.error}`);
  });

  // ============================================================
  // 提取入口
  // ============================================================
  function extract(mode) {
    const sourceUrl = location.href;
    const title = document.title || sourceUrl;

    switch (mode) {
      case CLIP_MODE.FULL_PAGE:
        return buildPayload(title, sourceUrl, fullPageMarkdown());

      case CLIP_MODE.SIMPLIFIED_ARTICLE: {
        const article = readabilityExtract(document);
        const md = htmlToMarkdown(article.html);
        return buildPayload(title || article.title, sourceUrl, md, { description: article.excerpt });
      }

      case CLIP_MODE.BOOKMARK: {
        const description = getMetaDescription();
        const md = bookmarkMarkdown(title, sourceUrl, description);
        return buildPayload(title, sourceUrl, md, { description });
      }

      case CLIP_MODE.SELECTION: {
        const sel = window.getSelection();
        const text = sel ? sel.toString() : '';
        if (!text.trim()) {
          throw new Error('当前没有选中的内容');
        }
        // 优先使用选中区域的 HTML（保留链接/格式），否则退化为纯文本
        let html = '';
        if (sel && sel.rangeCount > 0) {
          const range = sel.getRangeAt(0);
          const fragment = range.cloneContents();
          const container = document.createElement('div');
          container.appendChild(fragment);
          html = container.innerHTML;
        }
        const md = html ? htmlToMarkdown(html) : escapeMarkdown(text);
        return buildPayload(title, sourceUrl, md);
      }

      default:
        throw new Error('未知的剪藏模式：' + mode);
    }
  }

  function buildPayload(title, sourceUrl, content, extra) {
    return Object.assign(
      {
        title: title,
        sourceUrl: sourceUrl,
        content: content,
        tags: ['web-clip'],
      },
      extra || {}
    );
  }

  // ============================================================
  // full_page：整页 HTML → Markdown
  // ============================================================
  function fullPageMarkdown() {
    // 克隆 body，移除 script/style/noscript/template 等噪声节点
    const clone = document.body.cloneNode(true);
    removeNoise(clone);
    return htmlToMarkdown(clone.innerHTML);
  }

  // ============================================================
  // bookmark：仅标题 + URL + 描述
  // ============================================================
  function bookmarkMarkdown(title, url, description) {
    const lines = [`# ${title}`, '', `> 来源：${url}`];
    if (description) {
      lines.push('', `> ${description}`);
    }
    lines.push('', `链接：${url}`);
    return lines.join('\n');
  }

  function getMetaDescription() {
    const meta =
      document.querySelector('meta[name="description"]') ||
      document.querySelector('meta[property="og:description"]');
    return meta ? (meta.getAttribute('content') || '').trim() : '';
  }

  // ============================================================
  // 简化版 Readability：从页面中找出最可能是正文的容器
  // ============================================================
  function readabilityExtract(doc) {
    const clone = doc.cloneNode(true);

    // 1. 移除明显的噪声节点
    removeNoise(clone);

    // 2. 优先尝试 <article> / <main>
    let candidate =
      clone.querySelector('article') ||
      clone.querySelector('main') ||
      clone.querySelector('[role="main"]');

    // 3. 否则按评分挑选文本密度最高的容器
    if (!candidate) {
      candidate = pickBestCandidate(clone);
    }

    if (!candidate) {
      // 兜底：使用 body
      candidate = clone.body || clone.documentElement;
    }

    // 4. 在候选容器内进一步清理
    cleanCandidate(candidate);

    const title = (doc.title || '').trim();
    const excerpt = getExcerpt(candidate);
    return {
      title: title,
      html: candidate.innerHTML,
      excerpt: excerpt,
    };
  }

  function removeNoise(root) {
    const selectors = [
      'script',
      'style',
      'noscript',
      'template',
      'iframe',
      'svg',
      'canvas',
      'nav',
      'header',
      'footer',
      'aside',
      'form',
      'button',
      'input',
      'select',
      'textarea',
      '[aria-hidden="true"]',
      '[role="navigation"]',
      '[role="banner"]',
      '[role="search"]',
      '[role="complementary"]',
      '.ad',
      '.ads',
      '.advert',
      '.advertisement',
      '.sidebar',
      '.comment',
      '.comments',
      '.share',
      '.sharing',
      '.related',
      '.recommend',
      '.newsletter',
      '.subscribe',
      '.popup',
      '.modal',
    ];
    const nodes = root.querySelectorAll(selectors.join(','));
    nodes.forEach((n) => n.parentNode && n.parentNode.removeChild(n));
  }

  function pickBestCandidate(root) {
    const blocks = root.querySelectorAll('div, section, article, td, li');
    let best = null;
    let bestScore = 0;
    blocks.forEach((b) => {
      const score = scoreBlock(b);
      if (score > bestScore) {
        bestScore = score;
        best = b;
      }
    });
    return best;
  }

  function scoreBlock(el) {
    const text = (el.innerText || '').trim();
    if (!text) return 0;
    const len = text.length;
    // 文本长度作为基础分
    let score = len;
    // 段落数量加权
    const paragraphs = el.querySelectorAll('p').length;
    score += paragraphs * 30;
    // 链接密度惩罚：链接文字占比越高越不像正文
    const linkText = Array.from(el.querySelectorAll('a')).reduce(
      (acc, a) => acc + (a.innerText || '').length,
      0
    );
    const linkDensity = len > 0 ? linkText / len : 0;
    score = score * (1 - linkDensity);
    // class/id 含常见正文关键词加分
    const ident = `${el.className || ''} ${el.id || ''}`.toLowerCase();
    if (/(article|content|post|entry|main|body|story)/.test(ident)) score *= 1.2;
    if (/(comment|sidebar|footer|header|nav|menu|ad|promo|share|related)/.test(ident)) score *= 0.5;
    return score;
  }

  function cleanCandidate(el) {
    // 移除候选容器内的空段落与隐藏元素
    el.querySelectorAll('p').forEach((p) => {
      if (!(p.innerText || '').trim()) p.parentNode && p.parentNode.removeChild(p);
    });
    el.querySelectorAll('[style*="display:none"],[style*="display: none"],[hidden]').forEach((n) => {
      n.parentNode && n.parentNode.removeChild(n);
    });
  }

  function getExcerpt(el) {
    const firstP = el.querySelector('p');
    const text = (firstP ? firstP.innerText : el.innerText || '').trim();
    if (!text) return '';
    return text.length > 200 ? text.slice(0, 200) + '…' : text;
  }

  // ============================================================
  // HTML → Markdown 转换器（简化版）
  // ============================================================
  function htmlToMarkdown(html) {
    if (!html) return '';
    const container = document.createElement('div');
    container.innerHTML = html;
    return nodeToMarkdown(container).trim();
  }

  function nodeToMarkdown(node) {
    let out = '';
    node.childNodes.forEach((child) => {
      out += renderNode(child);
    });
    return out;
  }

  function renderNode(node) {
    if (node.nodeType === Node.TEXT_NODE) {
      return escapeMarkdown(node.textContent);
    }
    if (node.nodeType !== Node.ELEMENT_NODE) {
      return '';
    }
    const tag = node.tagName.toLowerCase();
    const inner = nodeToMarkdown(node);

    switch (tag) {
      case 'h1':
        return `\n\n# ${inner.trim()}\n\n`;
      case 'h2':
        return `\n\n## ${inner.trim()}\n\n`;
      case 'h3':
        return `\n\n### ${inner.trim()}\n\n`;
      case 'h4':
        return `\n\n#### ${inner.trim()}\n\n`;
      case 'h5':
        return `\n\n##### ${inner.trim()}\n\n`;
      case 'h6':
        return `\n\n###### ${inner.trim()}\n\n`;
      case 'p':
        return `\n\n${inner.trim()}\n\n`;
      case 'br':
        return `  \n`;
      case 'hr':
        return `\n\n---\n\n`;
      case 'a': {
        const href = node.getAttribute('href') || '';
        const text = inner.trim() || href;
        if (!href) return text;
        return `[${text}](${href})`;
      }
      case 'img': {
        const src = node.getAttribute('src') || '';
        const alt = node.getAttribute('alt') || '';
        if (!src) return '';
        return `![${alt}](${src})`;
      }
      case 'strong':
      case 'b':
        return `**${inner.trim()}**`;
      case 'em':
      case 'i':
        return `*${inner.trim()}*`;
      case 'del':
      case 's':
      case 'strike':
        return `~~${inner.trim()}~~`;
      case 'code':
        return `\`${inner.trim()}\``;
      case 'pre': {
        const codeText = node.innerText || inner;
        return `\n\n\`\`\`\n${codeText.replace(/\n+$/, '')}\n\`\`\`\n\n`;
      }
      case 'blockquote':
        return `\n${inner
          .trim()
          .split('\n')
          .map((l) => `> ${l}`)
          .join('\n')}\n\n`;
      case 'ul':
        return `\n${renderList(node, false)}\n`;
      case 'ol':
        return `\n${renderList(node, true)}\n`;
      case 'li':
        // li 由 renderList 统一处理，单独出现时按无序项渲染
        return `- ${inner.trim()}\n`;
      case 'table':
        return `\n\n${renderTable(node)}\n\n`;
      case 'thead':
      case 'tbody':
      case 'tfoot':
      case 'tr':
      case 'th':
      case 'td':
        // 表格相关由 renderTable 处理
        return inner;
      case 'div':
      case 'section':
      case 'article':
      case 'main':
      case 'span':
        return inner;
      default:
        return inner;
    }
  }

  function renderList(listNode, ordered) {
    const items = listNode.querySelectorAll(':scope > li');
    let out = '';
    let i = 1;
    items.forEach((li) => {
      const text = nodeToMarkdown(li).trim();
      const marker = ordered ? `${i}. ` : '- ';
      // 处理嵌套列表
      const nested = li.querySelectorAll(':scope > ul, :scope > ol');
      let mainText = text;
      let nestedText = '';
      if (nested.length > 0) {
        // 简化处理：把嵌套列表内容缩进追加
        nested.forEach((n) => {
          mainText = mainText.replace(nodeToMarkdown(n), '').trim();
          nestedText +=
            '\n' +
            renderList(n, n.tagName.toLowerCase() === 'ol')
              .split('\n')
              .filter(Boolean)
              .map((l) => '  ' + l)
              .join('\n');
        });
      }
      out += `${marker}${mainText}${nestedText}\n`;
      i++;
    });
    return out;
  }

  function renderTable(tableNode) {
    const rows = tableNode.querySelectorAll('tr');
    if (rows.length === 0) return '';
    const matrix = [];
    let colCount = 0;
    rows.forEach((tr) => {
      const cells = Array.from(tr.querySelectorAll('th, td')).map((c) =>
        nodeToMarkdown(c).trim().replace(/\|/g, '\\|').replace(/\n+/g, ' ')
      );
      if (cells.length > colCount) colCount = cells.length;
      matrix.push(cells);
    });
    if (colCount === 0) return '';

    const header = matrix[0];
    while (header.length < colCount) header.push('');
    const separator = Array(colCount).fill('---');
    const lines = [`| ${header.join(' | ')} |`, `| ${separator.join(' | ')} |`];
    for (let r = 1; r < matrix.length; r++) {
      while (matrix[r].length < colCount) matrix[r].push('');
      lines.push(`| ${matrix[r].join(' | ')} |`);
    }
    return lines.join('\n');
  }

  function escapeMarkdown(text) {
    // P0 修复: 原实现直接返回原文，未转义 Markdown 特殊字符，
    // 导致剪藏的网页文本破坏生成的 Markdown 结构。
    // 转义以下字符：\ ` * _ { } [ ] ( ) # + - ! | ~
    return text
      .replace(/\\/g, '\\\\')
      .replace(/`/g, '\\`')
      .replace(/\*/g, '\\*')
      .replace(/_/g, '\\_')
      .replace(/\{/g, '\\{')
      .replace(/\}/g, '\\}')
      .replace(/\[/g, '\\[')
      .replace(/\]/g, '\\]')
      .replace(/\(/g, '\\(')
      .replace(/\)/g, '\\)')
      .replace(/#/g, '\\#')
      .replace(/\+/g, '\\+')
      .replace(/-/g, '\\-')
      .replace(/!/g, '\\!')
      .replace(/\|/g, '\\|')
      .replace(/~/g, '\\~');
  }

  // ============================================================
  // 页面内轻量提示
  // ============================================================
  function showOverlay(message) {
    const box = document.createElement('div');
    box.textContent = message;
    Object.assign(box.style, {
      position: 'fixed',
      right: '20px',
      bottom: '20px',
      zIndex: '2147483647',
      padding: '10px 16px',
      background: '#1f2937',
      color: '#ffffff',
      fontSize: '14px',
      borderRadius: '6px',
      boxShadow: '0 4px 12px rgba(0,0,0,0.2)',
      fontFamily: 'system-ui, -apple-system, sans-serif',
      maxWidth: '320px',
      wordBreak: 'break-word',
    });
    document.documentElement.appendChild(box);
    setTimeout(() => {
      if (box.parentNode) box.parentNode.removeChild(box);
    }, 3000);
  }
})();
