importScripts("domain-normalizer.js");

const applicationIdentifier = "com.ziadnasreldin.zoidzero";

async function reportActiveTab() {
  const tabs = await browser.tabs.query({ active: true, currentWindow: true });
  const tab = tabs[0];
  if (!tab?.url) {
    await sendMessage(ZoidDomain.unavailableMessage());
    return;
  }
  const message = ZoidDomain.activityMessage(tab.url);
  if (!message) {
    await sendMessage(ZoidDomain.unavailableMessage());
    return;
  }
  await sendMessage(message);
}

async function sendMessage(message) {
  try {
    await browser.runtime.sendNativeMessage(applicationIdentifier, message);
  } catch {
    return;
  }
}

browser.tabs.onActivated.addListener(reportActiveTab);
browser.tabs.onUpdated.addListener((_tabID, changeInfo, tab) => {
  if (tab.active && changeInfo.url) {
    reportActiveTab();
  }
});
browser.windows.onFocusChanged.addListener((windowID) => {
  if (windowID !== browser.windows.WINDOW_ID_NONE) {
    reportActiveTab();
  }
});
browser.permissions.onRemoved.addListener(() => {
  sendMessage(ZoidDomain.unavailableMessage());
});
reportActiveTab();
