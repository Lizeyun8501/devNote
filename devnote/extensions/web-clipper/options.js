// DevNote Web Clipper —— 设置页脚本

const DEFAULT_SETTINGS = {
  serverUrl: 'https://sync.devnote.app',
  apiToken: '',
  defaultFolderId: '',
  defaultMode: 'simplified_article',
};

// ============================================================
// S6: Token 加密存储 —— 与 background.js 对称的 AES-GCM 加解密
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

document.addEventListener('DOMContentLoaded', async () => {
  const settings = await getSettings();
  document.getElementById('serverUrl').value = settings.serverUrl || '';
  document.getElementById('apiToken').value = settings.apiToken || '';
  document.getElementById('defaultFolderId').value = settings.defaultFolderId || '';
  document.getElementById('defaultMode').value = settings.defaultMode || 'simplified_article';

  document.getElementById('save').addEventListener('click', save);
  document.getElementById('test').addEventListener('click', testConnection);
});

async function save() {
  const plainToken = (document.getElementById('apiToken').value || '').trim();
  // S6: 加密 token 后再存储
  const encryptedToken = await encryptToken(plainToken);
  const settings = {
    serverUrl: (document.getElementById('serverUrl').value || '').trim(),
    apiToken: encryptedToken,
    defaultFolderId: (document.getElementById('defaultFolderId').value || '').trim(),
    defaultMode: document.getElementById('defaultMode').value,
  };
  if (!settings.serverUrl) {
    setStatus('请填写服务器地址', 'error');
    return;
  }
  if (!plainToken) {
    setStatus('请填写 API Token', 'error');
    return;
  }
  await new Promise((resolve) => {
    chrome.storage.local.set(settings, resolve);
  });
  setStatus('已保存', 'success');
}

async function testConnection() {
  const serverUrl = (document.getElementById('serverUrl').value || '').trim();
  const apiToken = (document.getElementById('apiToken').value || '').trim();
  if (!serverUrl || !apiToken) {
    setStatus('请先填写服务器地址与 API Token', 'error');
    return;
  }
  setStatus('测试中…', '');
  try {
    // 通过访问 sync status 端点验证 token 与服务器可达性
    const url = `${serverUrl.replace(/\/+$/, '')}/api/v1/sync/status?device_id=web-clipper`;
    const resp = await fetch(url, {
      headers: { Authorization: `Bearer ${apiToken}` },
    });
    if (resp.ok) {
      setStatus('连接成功', 'success');
    } else if (resp.status === 401 || resp.status === 403) {
      setStatus('Token 无效或已过期', 'error');
    } else {
      setStatus(`服务器返回 ${resp.status}`, 'error');
    }
  } catch (err) {
    setStatus(`连接失败：${err.message}`, 'error');
  }
}

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

function setStatus(text, cls) {
  const el = document.getElementById('status');
  el.textContent = text;
  el.className = 'status ' + (cls || '');
}
