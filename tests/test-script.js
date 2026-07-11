const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const rootDir = path.resolve(__dirname, "..");
const scriptPath = path.join(rootDir, "config", "Script.js");
const source = fs.readFileSync(scriptPath, "utf8");
vm.runInThisContext(source, { filename: "config/Script.js" });

function run(config) {
  return main(JSON.parse(JSON.stringify(config)), "test-profile");
}

function groupByName(config, name) {
  return (config["proxy-groups"] || []).find((group) => group.name === name);
}

{
  const output = run({
    proxies: [{ name: "US" }, { name: "TW" }, { name: "Proxies" }, { name: "SG-A" }],
    "proxy-groups": [],
    "rule-providers": {
      test: { type: "inline", behavior: "domain", proxy: "Proxies", payload: ["example.test"] }
    },
    rules: ["MATCH,DIRECT"]
  });

  const usGroup = groupByName(output, "US Group");
  const twGroup = groupByName(output, "TW Group");
  assert(usGroup, "US node collision must allocate US Group");
  assert(twGroup, "TW node collision must allocate TW Group");
  assert.deepStrictEqual(usGroup.proxies, ["US"]);
  assert.deepStrictEqual(twGroup.proxies, ["TW"]);
  assert(!usGroup.proxies.includes(usGroup.name), "US group must not reference itself");
  assert(!twGroup.proxies.includes(twGroup.name), "TW group must not reference itself");
  assert.deepStrictEqual(groupByName(output, "Claude").proxies, ["US Group"]);
  assert.deepStrictEqual(groupByName(output, "AI").proxies, ["US Group", "TW Group"]);
  assert(groupByName(output, "Proxies Group"), "Proxies node collision must allocate Proxies Group");
  assert.strictEqual(output["rule-providers"].test.proxy, "Proxies Group");
}

{
  const output = run({
    proxies: [{ name: "US-bootstrap" }],
    "proxy-providers": {
      airport: { type: "http", url: "https://example.invalid/provider" }
    },
    "proxy-groups": [
      { name: "All Provider Nodes", type: "select", use: ["airport"] },
      { name: "US Provider", type: "url-test", use: ["airport"] }
    ],
    rules: ["MATCH,DIRECT"]
  });

  assert(groupByName(output, "All Provider Nodes"), "mixed subscription must keep provider groups");
  assert(groupByName(output, "US Provider"), "mixed subscription must keep regional provider groups");
  assert(groupByName(output, "Proxies").proxies.includes("All Provider Nodes"));
  assert(groupByName(output, "US").proxies.includes("US Provider"));
}

{
  const output = run({
    "proxy-providers": {
      airport: { type: "inline", payload: [{ name: "US-A" }, { name: "TW-A" }, { name: "SG-A" }] }
    },
    "proxy-groups": [
      { name: "Proxies", type: "select", use: ["airport"] },
      { name: "US", type: "url-test", use: ["airport"], filter: "US" },
      { name: "TW", type: "url-test", use: ["airport"], filter: "TW" },
      { name: "SG", type: "url-test", use: ["airport"], filter: "SG" },
      { name: "Claude", type: "select", use: ["airport"], filter: "US|HK" },
      { name: "AI", type: "select", use: ["airport"], "include-all": true },
      { name: "Exchange", type: "select", use: ["airport"], "exclude-filter": "TW|SG" }
    ],
    rules: ["MATCH,Proxies"]
  });

  assert.deepStrictEqual(groupByName(output, "Proxies").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "US").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "TW").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "SG").use, ["airport"]);
  assert.deepStrictEqual(groupByName(output, "Claude").proxies, ["US"]);
  assert.deepStrictEqual(groupByName(output, "AI").proxies, ["US", "TW"]);
  assert.deepStrictEqual(groupByName(output, "Exchange").proxies, ["TW", "SG"]);
  assert.strictEqual(groupByName(output, "Claude").use, undefined);
  assert.strictEqual(groupByName(output, "Claude").filter, undefined);
  assert.strictEqual(groupByName(output, "AI").use, undefined);
  assert.strictEqual(groupByName(output, "AI")["include-all"], undefined);
  assert.strictEqual(groupByName(output, "Exchange").use, undefined);
  assert.strictEqual(groupByName(output, "Exchange")["exclude-filter"], undefined);
}

{
  const output = run({
    proxies: [{ name: "US-A" }],
    "proxy-groups": [{ name: "proxies", type: "select", proxies: ["US-A"] }],
    rules: ["MATCH,Proxies"]
  });

  assert(groupByName(output, "proxies"), "case-insensitive existing group must be reused");
  assert(output.rules.includes("MATCH,proxies"), "rule target must follow reused group casing");
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "TW-A" }, { name: "SG-A" }],
    "proxy-groups": [],
    rules: ["DOMAIN,example.test,DIRECT"]
  });

  assert(output.rules[0].startsWith("DOMAIN-SUFFIX,okx.com,"), "exchange rules must be inserted before narrow-only rules");
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "Proxies" }],
    "proxy-groups": [],
    rules: ["FINAL,Proxies", "FINAL,REJECT"]
  });

  assert(output.rules.includes("MATCH,Proxies Group"), "legacy FINAL rule must become a valid MATCH rule with the allocated group name");
  assert(!output.rules.includes("MATCH,REJECT"), "legacy FINAL reject rule must be removed with other reject rules");
}

{
  const output = run({
    proxies: [{ name: "US-A" }, { name: "Proxies" }],
    "proxy-groups": [],
    rules: [
      "AND,((DOMAIN,example.test),(NETWORK,TCP)),Proxies",
      "OR,((DOMAIN,ads.example.test),(NETWORK,UDP)),REJECT"
    ]
  });

  assert(output.rules.includes("AND,((DOMAIN,example.test),(NETWORK,TCP)),Proxies Group"), "logical rule target must follow the allocated managed group name");
  assert(!output.rules.some((rule) => rule.includes("ads.example.test")), "logical reject rule must be removed with other reject rules");
}

console.log("Script.js regression tests passed");
