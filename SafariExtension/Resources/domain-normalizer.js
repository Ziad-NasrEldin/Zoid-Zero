(function initializeDomainTools(root) {
const compoundPublicSuffixes = new Set([
  "ac.uk",
  "co.in",
  "co.jp",
  "co.nz",
  "co.uk",
  "com.ar",
  "com.au",
  "com.br",
  "com.cn",
  "com.eg",
  "com.hk",
  "com.mx",
  "com.sa",
  "com.sg",
  "com.tr",
  "com.tw",
  "edu.au",
  "edu.eg",
  "gov.au",
  "gov.uk",
  "gov.za",
  "net.au",
  "net.cn",
  "net.nz",
  "net.uk",
  "org.au",
  "org.cn",
  "org.nz",
  "org.uk",
]);

const privatePublicSuffixes = new Set(["github.io"]);

function registrableDomain(address) {
  let url;
  try {
    url = new URL(address);
  } catch {
    return null;
  }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return null;
  }
  const host = url.hostname.toLowerCase().replace(/\.+$/, "");
  if (!host) {
    return null;
  }
  if (host === "localhost" || isIPAddress(host)) {
    return host;
  }

  const labels = host.split(".");
  if (labels.length < 2) {
    return host;
  }
  let suffixLength = 1;
  const rules = new Set([
    ...compoundPublicSuffixes,
    ...privatePublicSuffixes,
  ]);
  for (let length = 2; length <= Math.min(3, labels.length); length += 1) {
    const suffix = labels.slice(-length).join(".");
    if (rules.has(suffix)) {
      suffixLength = length;
    }
  }
  return labels.slice(-(suffixLength + 1)).join(".");
}

function activityMessage(address, timestampMilliseconds = Date.now()) {
  const domain = registrableDomain(address);
  if (!domain) {
    return null;
  }
  return {
    kind: "activeDomain",
    domain,
    timestampMilliseconds,
  };
}

function unavailableMessage(timestampMilliseconds = Date.now()) {
  return {
    kind: "domainUnavailable",
    timestampMilliseconds,
  };
}

function isIPAddress(host) {
  if (host.includes(":")) {
    return /^[0-9a-f:.]+$/i.test(host);
  }
  const parts = host.split(".");
  return (
    parts.length === 4
    && parts.every((part) => {
      if (!/^\d+$/.test(part)) {
        return false;
      }
      const value = Number(part);
      return value >= 0 && value <= 255;
    })
  );
}

const domainTools = { activityMessage, registrableDomain, unavailableMessage };
root.ZoidDomain = domainTools;
if (typeof module !== "undefined" && module.exports) {
  module.exports = domainTools;
}
})(globalThis);
