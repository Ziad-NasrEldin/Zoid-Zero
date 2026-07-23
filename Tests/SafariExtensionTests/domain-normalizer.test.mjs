import assert from "node:assert/strict";
import test from "node:test";

import domainTools from "../../SafariExtension/Resources/domain-normalizer.js";

const { activityMessage, registrableDomain, unavailableMessage } = domainTools;

test("normalizes active URLs to registrable domains", () => {
  assert.equal(
    registrableDomain("https://www.youtube.com/watch?v=secret"),
    "youtube.com",
  );
  assert.equal(
    registrableDomain("https://docs.example.co.uk/private?q=secret"),
    "example.co.uk",
  );
  assert.equal(
    registrableDomain("https://subdomain.github.io/private"),
    "subdomain.github.io",
  );
});

test("rejects addresses that are not HTTP websites", () => {
  assert.equal(registrableDomain("file:///private/secret"), null);
  assert.equal(registrableDomain("about:blank"), null);
  assert.equal(registrableDomain("not a url"), null);
});

test("activity messages never contain browsing details", () => {
  const message = activityMessage(
    "https://github.com/private/repository?token=secret#fragment",
    1_753_200_000_000,
  );

  assert.deepEqual(message, {
    kind: "activeDomain",
    domain: "github.com",
    timestampMilliseconds: 1_753_200_000_000,
  });
  assert.equal(JSON.stringify(message).includes("private"), false);
  assert.equal(JSON.stringify(message).includes("secret"), false);
});

test("unavailable messages close website attribution without browsing data", () => {
  assert.deepEqual(unavailableMessage(1_753_200_000_000), {
    kind: "domainUnavailable",
    timestampMilliseconds: 1_753_200_000_000,
  });
});
