// DevNote Web Clipper —— background service worker (Manifest V3)
//
// 职责：
//   1. 扩展安装/启动时创建右键菜单（全文 / 正文 / 书签 / 选中内容）。
//   2. 监听右键菜单点击，向当前标签页的 content script 发送剪藏指令。
//   3. 统一管理用户认证 token 与服务器地址（chrome.storage.local），
//      并在收到 content script / popup 回传的剪藏内容后调用 sync-server API。

const CLIP_MODE = {
  FULL_PAGE: 'full_page',
  SIMPLIFIED_ARTICLE: 'simplified_article',
  BOOKMARK: 'bookmark',
  SELECTION: 'selection',
};

const MENU_ID = {
  FULL_PAGE: 'devnote-clip-full',
  SIMPLIFIED_ARTICLE: 'devnote-clip-article',
  BOOKMARK: 'devnote-clip-bookmark',
  SELECTION: 'devnote-clip-selection',
};

// ---- 默认配置 ----
const DEFAULT_SETTINGS = {
  serverUrl: 'https://sync.devnote.app',
  apiToken: '',
  defaultFolderId: '',
  defaultMode: CLIP_MODE.SIMPLIFIED_ARTICLE,
};

// ---- 右键菜单 ----
function createContextMenus() {
  chrome.contextMenus.removeAll(() => {
    chrome.contextMenus.create({
      id: MENU_ID.FULL_PAGE,
      title: '剪藏到 DevNote（整页）',
      contexts: ['page'],
    });
    chrome.contextMenus.create({
      id: MENU_ID.SIMPLIFIED_ARTICLE,
      title: '剪藏正文到 DevNote',
      contexts: ['page', 'selection'],
    });
    chrome.contextMenus.create({
      id: MENU_ID.BOOKMARK,
      title: '剪藏书签到 DevNote',
      contexts: ['page'],
    });
    chrome.contextMenus.create({
      id: MENU_ID.SELECTION,
      title: '剪藏选中内容到 DevNote',
      contexts: ['selection'],
    });
  });
}

chrome.runtime.onInstalled.addListener(() => {
  createContextMenus();
  // 写入默认配置（仅当尚未设置时）
  chrome.storage.local.get(DEFAULT_SETTINGS, (existing) => {
    const merged = { ...DEFAULT_SETTINGS, ...existing };
    chrome.storage.local.set(merged);
  });
});

chrome.runtime.onStartup.addListener(() => {
  createContextMenus();
});

// ---- 右键菜单点击 ----
chrome.contextMenus.onClicked.addListener((info, tab) => {
  let mode = null;
  switch (info.menuItemId) {
    case MENU_ID.FULL_PAGE:
      mode = CLIP_MODE.FULL_PAGE;
      break;
    case MENU_ID.SIMPLIFIED_ARTICLE:
      mode = CLIP_MODE.SIMPLIFIED_ARTICLE;
      break;
    case MENU_ID.BOOKMARK:
      mode = CLIP_MODE.BOOKMARK;
      break;
    case MENU_ID.SELECTION:
      mode = CLIP_MODE.SELECTION;
      break;
    default:
      return;
  }
  if (!tab || !tab.id) return;
  sendClipRequest(tab.id, mode);
});

// ---- 来自 popup 的消息 ----
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg && msg.type === 'CLIP_FROM_POPUP') {
    // popup 请求在当前标签页执行剪藏
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      const tab = tabs && tabs[0];
      if (!tab || !tab.id) {
        sendResponse({ ok: false, error: '没有活动标签页' });
        return;
      }
      // 先让 content script 提取内容，再由 background 统一上传
      chrome.tabs.sendMessage(
        tab.id,
        { type: 'EXTRACT_CONTENT', mode: msg.mode },
        (extractResp) => {
          if (chrome.runtime.lastError) {
            sendResponse({ ok: false, error: chrome.runtime.lastError.message });
            return;
          }
          if (!extractResp || !extractResp.ok) {
            sendResponse({ ok: false, error: (extractResp && extractResp.error) || '提取内容失败' });
            return;
          }
          uploadClip(extractResp.payload)
            .then((res) => sendResponse({ ok: true, data: res }))
            .catch((err) => sendResponse({ ok: false, error: err.message }));
        }
      );
    });
    return true; // 异步响应
  }

  if (msg && msg.type === 'EXTRACTED_CONTENT') {
    // content script 主动回传（右键菜单触发流程）
    uploadClip(msg.payload)
      .then(() => {
        notifyTab(sender.tab && sender.tab.id, { ok: true });
      })
      .catch((err) => {
        notifyTab(sender.tab && sender.tab.id, { ok: false, error: err.message });
      });
  }
});

// ---- 向 content script 发送剪藏指令 ----
function sendClipRequest(tabId, mode) {
  chrome.tabs.sendMessage(
    tabId,
    { type: 'EXTRACT_CONTENT', mode },
    (resp) => {
      if (chrome.runtime.lastError) {
        // content script 可能未注入（如 chrome:// 页面），尝试程序化注入
        chrome.scripting &&
          chrome.scripting.executeScript(
            { target: { tabId }, files: ['content.js'] },
            () => {
              chrome.tabs.sendMessage(tabId, { type: 'EXTRACT_CONTENT', mode });
            }
          );
        return;
      }
      if (resp && resp.ok) {
        uploadClip(resp.payload).catch((err) => {
          notifyTab(tabId, { ok: false, error: err.message });
        });
      }
    }
  );
}

function notifyTab(tabId, payload) {
  if (!tabId) return;
  chrome.tabs.sendMessage(tabId, { type: 'CLIP_RESULT', payload }).catch(() => {
    // 通知失败可忽略
  });
}

// ---- 读取配置 ----
function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.local.get(DEFAULT_SETTINGS, (s) => {
      resolve({ ...DEFAULT_SETTINGS, ...s });
    });
  });
}

// ---- 调用 sync-server 剪藏 API ----
async function uploadClip(payload) {
  const settings = await getSettings();
  if (!settings.apiToken) {
    throw new Error('未配置 API Token，请在扩展设置页填写');
  }
  const base = (settings.serverUrl || '').replace(/\/+$/, '');
  if (!base) {
    throw new Error('未配置 DevNote 服务器地址');
  }
  const url = `${base}/api/v1/notes/clip`;

  const body = {
    title: payload.title,
    content: payload.content,
    source_url: payload.sourceUrl,
    folder_id: settings.defaultFolderId || payload.folderId || '',
    tags: payload.tags || [],
  };

  const resp = await fetch(url, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${settings.apiToken}`,
    },
    body: JSON.stringify(body),
  });

  if (!resp.ok) {
    let detail = '';
    try {
      const errJson = await resp.json();
      detail = errJson.error || JSON.stringify(errJson);
    } catch (_) {
      detail = await resp.text().catch(() => '');
    }
    throw new Error(`服务器返回 ${resp.status}: ${detail}`);
  }
  return resp.json();
}
