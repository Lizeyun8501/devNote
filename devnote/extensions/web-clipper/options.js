// DevNote Web Clipper —— 设置页脚本

const DEFAULT_SETTINGS = {
  serverUrl: 'https://sync.devnote.app',
  apiToken: '',
  defaultFolderId: '',
  defaultMode: 'simplified_article',
};

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
  const settings = {
    serverUrl: (document.getElementById('serverUrl').value || '').trim(),
    apiToken: (document.getElementById('apiToken').value || '').trim(),
    defaultFolderId: (document.getElementById('defaultFolderId').value || '').trim(),
    defaultMode: document.getElementById('defaultMode').value,
  };
  if (!settings.serverUrl) {
    setStatus('请填写服务器地址', 'error');
    return;
  }
  if (!settings.apiToken) {
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

function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.local.get(DEFAULT_SETTINGS, (s) => {
      resolve({ ...DEFAULT_SETTINGS, ...s });
    });
  });
}

function setStatus(text, cls) {
  const el = document.getElementById('status');
  el.textContent = text;
  el.className = 'status ' + (cls || '');
}
