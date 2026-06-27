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

// ============================================================
// S6: Token 加密存储 —— 使用 Web Crypto API 加密 token，避免明文存储
// 使用设备本地派生的 AES-GCM 密钥，密钥材料存储在 chrome.storage.local
// 中（与密文同域），属于纵深防御，主要防止日志/调试时意外泄漏明文。
// ============================================================
const TOKEN_KEY_NAME = 'tokenEncryptionKey';
const TOKEN_IV_LEN = 12;

async function getOrCreateEncryptionKey() {
  const stored = await new Promise((resolve) => {
    chrome.storage.local.get([TOKEN_KEY_NAME], (result) => resolve(result[TOKEN_KEY_NAME]));
  });

  if (stored) {
    const keyData = new Uint8Array(stored);
    return crypto.subtle.importKey(
      'raw',
      keyData,
      { name: 'AES-GCM' },
      false,
      ['encrypt', 'decrypt']
    );
  }

  const key = await crypto.subtle.generateKey(
    { name: 'AES-GCM', length: 256 },
    true,
    ['encrypt', 'decrypt']
  );
  const exported = await crypto.subtle.exportKey('raw', key);
  chrome.storage.local.set({ [TOKEN_KEY_NAME]: Array.from(new Uint8Array(exported)) });
  return key;
}

async function encryptToken(token) {
  if (!token) return '';
  const key = await getOrCreateEncryptionKey();
  const iv = crypto.getRandomValues(new Uint8Array(TOKEN_IV_LEN));
  const encoded = new TextEncoder().encode(token);
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    encoded
  );
  const combined = new Uint8Array(iv.length + ciphertext.byteLength);
  combined.set(iv, 0);
  combined.set(new Uint8Array(ciphertext), iv.length);
  return btoa(String.fromCharCode.apply(null, combined));
}

async function decryptToken(encryptedB64) {
  if (!encryptedB64) return '';
  try {
    const key = await getOrCreateEncryptionKey();
    const combined = new Uint8Array(
      atob(encryptedB64).split('').map((c) => c.charCodeAt(0))
    );
    const iv = combined.slice(0, TOKEN_IV_LEN);
    const ciphertext = combined.slice(TOKEN_IV_LEN);
    const plaintext = await crypto.subtle.decrypt(
      { name: 'AES-GCM', iv },
      key,
      ciphertext
    );
    return new TextDecoder().decode(plaintext);
  } catch (e) {
    console.warn('Failed to decrypt token, returning empty', e);
    return '';
  }
}

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
async function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.local.get(DEFAULT_SETTINGS, async (s) => {
      const settings = { ...DEFAULT_SETTINGS, ...s };
      // S6: 解密存储的 token
      if (settings.apiToken) {
        settings.apiToken = await decryptToken(settings.apiToken);
      }
      resolve(settings);
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
