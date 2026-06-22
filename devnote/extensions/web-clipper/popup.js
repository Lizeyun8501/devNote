// DevNote Web Clipper —— popup 脚本

const DEFAULT_SETTINGS = {
  serverUrl: 'https://sync.devnote.app',
  apiToken: '',
  defaultFolderId: '',
  defaultMode: 'simplified_article',
};

document.addEventListener('DOMContentLoaded', async () => {
  const settings = await getSettings();
  const tab = await getCurrentTab();

  // 渲染页面信息
  document.getElementById('pageTitle').textContent = (tab && tab.title) || '（无标题）';
  document.getElementById('pageUrl').textContent = (tab && tab.url) || '';

  // 未登录态切换
  if (!settings.apiToken) {
    document.getElementById('loggedIn').classList.add('hidden');
    document.getElementById('loggedOut').classList.remove('hidden');
  } else {
    document.getElementById('loggedIn').classList.remove('hidden');
    document.getElementById('loggedOut').classList.add('hidden');
    const serverInfo = document.getElementById('serverInfo');
    try {
      const host = new URL(settings.serverUrl).host;
      serverInfo.textContent = host;
    } catch (_) {
      serverInfo.textContent = settings.serverUrl;
    }
  }

  // 绑定模式按钮
  document.querySelectorAll('.mode-btn').forEach((btn) => {
    btn.addEventListener('click', () => {
      const mode = btn.getAttribute('data-mode');
      clip(mode);
    });
  });

  // 设置入口
  document.getElementById('openOptions').addEventListener('click', openOptions);
  document.getElementById('openOptions2').addEventListener('click', openOptions);
});

async function clip(mode) {
  setStatus('正在剪藏…', 'loading');
  setButtonsDisabled(true);
  try {
    const resp = await chrome.runtime.sendMessage({ type: 'CLIP_FROM_POPUP', mode });
    if (resp && resp.ok) {
      setStatus('已剪藏到 DevNote', 'success');
    } else {
      setStatus(`剪藏失败：${(resp && resp.error) || '未知错误'}`, 'error');
    }
  } catch (err) {
    setStatus(`剪藏失败：${err.message}`, 'error');
  } finally {
    setButtonsDisabled(false);
  }
}

function setStatus(text, cls) {
  const el = document.getElementById('status');
  el.textContent = text;
  el.className = 'status ' + (cls || '');
}

function setButtonsDisabled(disabled) {
  document.querySelectorAll('.mode-btn').forEach((btn) => {
    btn.disabled = disabled;
  });
}

function getSettings() {
  return new Promise((resolve) => {
    chrome.storage.local.get(DEFAULT_SETTINGS, (s) => {
      resolve({ ...DEFAULT_SETTINGS, ...s });
    });
  });
}

function getCurrentTab() {
  return new Promise((resolve) => {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      resolve(tabs && tabs[0]);
    });
  });
}

function openOptions() {
  if (chrome.runtime.openOptionsPage) {
    chrome.runtime.openOptionsPage();
  } else {
    window.open(chrome.runtime.getURL('options.html'));
  }
}
